"""Background daemon: watches multiple folders and tags new/modified files."""
import time
import logging
import threading
import queue
from pathlib import Path
from datetime import datetime

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

from .config import load_config
from .db import get_conn, init_db, file_hash, needs_reindex, upsert_file, remove_file
from .extractor import get_category, extract_text
from .tagger import tag_file
from .sidecar import write_sidecar, delete_sidecar
from .taxonomy import approved_tags, resolve_tags, init_taxonomy

logger = logging.getLogger("filetagger.daemon")


class FileQueue:
    def __init__(self):
        self._queue = queue.Queue()
        self._seen = set()
        self._lock = threading.Lock()

    def put(self, path: str):
        with self._lock:
            if path not in self._seen:
                self._seen.add(path)
                self._queue.put(path)

    def get(self, timeout=1):
        path = self._queue.get(timeout=timeout)
        with self._lock:
            self._seen.discard(path)
        return path

    def task_done(self):
        self._queue.task_done()

    def qsize(self):
        return self._queue.qsize()


class FileEventHandler(FileSystemEventHandler):
    def __init__(self, file_queue: FileQueue, supported_extensions: set):
        self.queue = file_queue
        self.supported = supported_extensions

    def _should_process(self, path: str) -> bool:
        p = Path(path)
        if not p.is_file():
            return False
        if p.name.startswith("."):
            return False
        # Skip .TagStudio internals
        if ".TagStudio" in p.parts:
            return False
        if p.suffix.lower() not in self.supported:
            return False
        return True

    def on_created(self, event):
        if not event.is_directory and self._should_process(event.src_path):
            time.sleep(0.5)
            self.queue.put(event.src_path)

    def on_modified(self, event):
        if not event.is_directory and self._should_process(event.src_path):
            self.queue.put(event.src_path)

    def on_deleted(self, event):
        if not event.is_directory:
            self.queue.put(f"__DELETE__:{event.src_path}")

    def on_moved(self, event):
        if not event.is_directory:
            self.queue.put(f"__DELETE__:{event.src_path}")
            if self._should_process(event.dest_path):
                self.queue.put(event.dest_path)


class TagWorker(threading.Thread):
    def __init__(self, file_queue: FileQueue, config: dict, db_path: str):
        super().__init__(daemon=True, name="TagWorker")
        self.queue = file_queue
        self.config = config
        self.db_path = db_path
        self._stop_event = threading.Event()
        self.processed = 0
        self.errors = 0
        self.current_file = None

    def stop(self):
        self._stop_event.set()

    def run(self):
        conn = get_conn(self.db_path)
        logger.info("TagWorker started")
        while not self._stop_event.is_set():
            try:
                path = self.queue.get(timeout=1)
            except queue.Empty:
                continue
            try:
                if path.startswith("__DELETE__:"):
                    actual = path[len("__DELETE__:"):]
                    remove_file(conn, actual)
                    delete_sidecar(actual)
                    # Remove from TagStudio too
                    self._ts_remove(actual)
                    logger.info(f"Removed: {actual}")
                else:
                    self._process_file(conn, path)
            except Exception as e:
                logger.error(f"Worker error on {path}: {e}")
                self.errors += 1
            finally:
                self.queue.task_done()
        conn.close()
        logger.info("TagWorker stopped")

    def _find_watch_dir(self, path: str) -> str:
        """Return which watch_dir contains this path."""
        p = Path(path)
        for d in self.config.get("watch_dirs", []):
            try:
                p.relative_to(d)
                return d
            except ValueError:
                continue
        # Fallback to first
        dirs = self.config.get("watch_dirs", [])
        return dirs[0] if dirs else ""

    def _ts_remove(self, path: str):
        try:
            from .tagstudio import remove_from_tagstudio
            watch_dir = self._find_watch_dir(path)
            if watch_dir:
                remove_from_tagstudio(path, watch_dir)
        except Exception as e:
            logger.debug(f"TagStudio remove skipped: {e}")

    def _process_file(self, conn, path: str):
        p = Path(path)
        if not p.exists() or not p.is_file():
            return

        fhash = file_hash(path)
        if not needs_reindex(conn, path, fhash) and not self.config.get("retag_on_modify"):
            logger.debug(f"Skipping unchanged: {p.name}")
            return

        self.current_file = p.name
        logger.info(f"Processing: {p.name}")

        supported = self.config["supported_extensions"]
        category = get_category(p.suffix, supported)
        size_bytes = p.stat().st_size

        try:
            content = extract_text(path, category, self.config)
            current_approved = approved_tags()
            summary, ai_tags = tag_file(
                p.name, category, p.suffix.lower(),
                content, size_bytes, self.config,
                approved_tags=current_approved
            )
            good_tags, new_tags = resolve_tags(ai_tags, p.name)
            if new_tags:
                logger.info(f"Pending approval: {p.name} → new tags [{', '.join(new_tags)}]")

            upsert_file(conn, path, category, summary, good_tags, size_bytes, fhash)
            write_sidecar(path, good_tags, summary)

            # Write to TagStudio if library exists
            watch_dir = self._find_watch_dir(path)
            if watch_dir:
                self._write_tagstudio(path, good_tags, summary, watch_dir)

            self.processed += 1
            logger.info(f"Tagged: {p.name} → [{', '.join(good_tags)}]")
        except Exception as e:
            logger.error(f"Failed to tag {p.name}: {e}")
            upsert_file(conn, path, category, "", [], size_bytes, fhash, error=str(e))
            self.errors += 1
        finally:
            self.current_file = None

    def _write_tagstudio(self, path: str, tags: list, summary: str, watch_dir: str):
        try:
            from .tagstudio import write_to_tagstudio, library_exists
            if library_exists(watch_dir):
                write_to_tagstudio(path, tags, summary, watch_dir)
        except Exception as e:
            logger.debug(f"TagStudio write skipped: {e}")


class LibraryWatcher(threading.Thread):
    """
    Polls for TagStudio library existence across all watch dirs.
    Logs a helpful message when waiting, stays quiet once found.
    """
    def __init__(self, config: dict, stop_event: threading.Event):
        super().__init__(daemon=True, name="LibraryWatcher")
        self.config = config
        self._stop = stop_event
        self._found: set[str] = set()
        self._waiting_logged: set[str] = set()

    def run(self):
        from .tagstudio import library_exists, _ts_db_path
        while not self._stop.is_set():
            for watch_dir in self.config.get("watch_dirs", []):
                if watch_dir in self._found:
                    continue
                if library_exists(watch_dir):
                    if watch_dir in self._waiting_logged:
                        logger.info(
                            f"✓ TagStudio library found: {watch_dir} — tag sync active"
                        )
                    self._found.add(watch_dir)
                elif watch_dir not in self._waiting_logged:
                    db_path = _ts_db_path(watch_dir)
                    logger.info(
                        f"Waiting for TagStudio library at {db_path}\n"
                        f"  Open TagStudio → File → Open/Create Library → select '{watch_dir}'"
                    )
                    self._waiting_logged.add(watch_dir)
            self._stop.wait(30)


class Daemon:
    def __init__(self, config: dict = None):
        self.config = config or load_config()
        self.db_path = self.config["db_path"]
        self._conn = init_db(self.db_path)
        self._file_queue = FileQueue()
        self._worker = None
        self._observer = None
        self._lib_watcher = None
        self._stop_event = threading.Event()
        self._running = False
        init_taxonomy()

    @property
    def is_running(self) -> bool:
        return self._running

    @property
    def worker_stats(self) -> dict:
        if self._worker:
            return {
                "processed": self._worker.processed,
                "errors": self._worker.errors,
                "current_file": self._worker.current_file,
                "queue_size": self._file_queue.qsize(),
            }
        return {"processed": 0, "errors": 0, "current_file": None, "queue_size": 0}

    def start(self):
        if self._running:
            return

        watch_dirs = self.config.get("watch_dirs", [])
        for d in watch_dirs:
            Path(d).mkdir(parents=True, exist_ok=True)

        supported = self.config["supported_extensions"]
        all_exts = {ext for exts in supported.values() for ext in exts}

        # Start tag worker
        self._worker = TagWorker(self._file_queue, self.config, self.db_path)
        self._worker.start()

        # Start TagStudio library watcher
        self._lib_watcher = LibraryWatcher(self.config, self._stop_event)
        self._lib_watcher.start()

        # Start filesystem observer — one handler, multiple scheduled dirs
        handler = FileEventHandler(self._file_queue, all_exts)
        self._observer = Observer()
        for watch_dir in watch_dirs:
            self._observer.schedule(handler, watch_dir, recursive=True)
            logger.info(f"Watching: {watch_dir}")
        self._observer.start()

        self._running = True
        logger.info(f"Daemon started, watching {len(watch_dirs)} director(y/ies)")

        # Initial scan of all watch dirs
        self._initial_scan(watch_dirs, all_exts)

    def _initial_scan(self, watch_dirs: list, all_exts: set):
        logger.info("Running initial scan...")
        count = 0
        for watch_dir in watch_dirs:
            for p in Path(watch_dir).rglob("*"):
                if (p.is_file()
                        and not p.name.startswith(".")
                        and ".TagStudio" not in p.parts
                        and p.suffix.lower() in all_exts):
                    fhash = file_hash(str(p))
                    if needs_reindex(self._conn, str(p), fhash):
                        self._file_queue.put(str(p))
                        count += 1
        logger.info(f"Initial scan queued {count} files")

    def stop(self):
        if not self._running:
            return
        logger.info("Stopping daemon...")
        self._stop_event.set()
        if self._observer:
            self._observer.stop()
            self._observer.join()
        if self._worker:
            self._worker.stop()
            self._worker.join(timeout=10)
        self._running = False
        logger.info("Daemon stopped")

    def retag_all(self):
        """Force re-tag all files across all watch dirs."""
        watch_dirs = self.config.get("watch_dirs", [])
        supported = self.config["supported_extensions"]
        all_exts = {ext for exts in supported.values() for ext in exts}
        count = 0
        for watch_dir in watch_dirs:
            for p in Path(watch_dir).rglob("*"):
                if (p.is_file()
                        and not p.name.startswith(".")
                        and ".TagStudio" not in p.parts
                        and p.suffix.lower() in all_exts):
                    self._file_queue.put(str(p))
                    count += 1
        logger.info(f"Queued {count} files for re-tagging")
        return count

    def retag_file(self, path: str):
        self._file_queue.put(path)

    def reload_watch_dirs(self):
        """Hot-reload watch dirs after config change (requires daemon restart)."""
        logger.info("Watch dir change detected — restart daemon to apply")