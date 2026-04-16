"""Background daemon: watches the files folder and tags new/modified files."""
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

logger = logging.getLogger("filetagger.daemon")


class FileQueue:
    """Thread-safe deduplicated file queue."""
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
        if p.suffix.lower() not in self.supported:
            return False
        return True

    def on_created(self, event):
        if not event.is_directory and self._should_process(event.src_path):
            logger.debug(f"New file detected: {event.src_path}")
            # Small delay to ensure file is fully written
            time.sleep(0.5)
            self.queue.put(event.src_path)

    def on_modified(self, event):
        if not event.is_directory and self._should_process(event.src_path):
            logger.debug(f"Modified file detected: {event.src_path}")
            self.queue.put(event.src_path)

    def on_deleted(self, event):
        if not event.is_directory:
            logger.debug(f"Deleted file: {event.src_path}")
            self.queue.put(f"__DELETE__:{event.src_path}")

    def on_moved(self, event):
        if not event.is_directory:
            self.queue.put(f"__DELETE__:{event.src_path}")
            if self._should_process(event.dest_path):
                self.queue.put(event.dest_path)


class TagWorker(threading.Thread):
    """Worker thread that processes files from the queue."""
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
        all_exts = {ext for exts in supported.values() for ext in exts}
        category = get_category(p.suffix, supported)
        size_bytes = p.stat().st_size

        try:
            content = extract_text(path, category, self.config)
            summary, tags = tag_file(
                p.name, category, p.suffix.lower(),
                content, size_bytes, self.config
            )
            upsert_file(conn, path, category, summary, tags, size_bytes, fhash)
            write_sidecar(path, tags, summary)
            self.processed += 1
            logger.info(f"Tagged: {p.name} → [{', '.join(tags)}]")
        except Exception as e:
            logger.error(f"Failed to tag {p.name}: {e}")
            upsert_file(conn, path, category, "", [], size_bytes, fhash, error=str(e))
            self.errors += 1
        finally:
            self.current_file = None


class Daemon:
    """Main daemon orchestrator."""
    def __init__(self, config: dict = None):
        self.config = config or load_config()
        self.db_path = self.config["db_path"]
        self._conn = init_db(self.db_path)
        self._file_queue = FileQueue()
        self._worker = None
        self._observer = None
        self._running = False

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
                "queue_size": self._file_queue._queue.qsize(),
            }
        return {"processed": 0, "errors": 0, "current_file": None, "queue_size": 0}

    def start(self):
        if self._running:
            logger.warning("Daemon already running")
            return

        watch_dir = self.config["watch_dir"]
        Path(watch_dir).mkdir(parents=True, exist_ok=True)

        supported = self.config["supported_extensions"]
        all_exts = {ext for exts in supported.values() for ext in exts}

        # Start worker
        self._worker = TagWorker(self._file_queue, self.config, self.db_path)
        self._worker.start()

        # Set up watchdog
        handler = FileEventHandler(self._file_queue, all_exts)
        self._observer = Observer()
        self._observer.schedule(handler, watch_dir, recursive=True)
        self._observer.start()

        self._running = True
        logger.info(f"Daemon started, watching: {watch_dir}")

        # Initial scan
        self._initial_scan(watch_dir, all_exts)

    def _initial_scan(self, watch_dir: str, all_exts: set):
        logger.info("Running initial scan...")
        count = 0
        for p in Path(watch_dir).rglob("*"):
            if p.is_file() and not p.name.startswith(".") and p.suffix.lower() in all_exts:
                fhash = file_hash(str(p))
                if needs_reindex(self._conn, str(p), fhash):
                    self._file_queue.put(str(p))
                    count += 1
        logger.info(f"Initial scan queued {count} files")

    def stop(self):
        if not self._running:
            return
        logger.info("Stopping daemon...")
        if self._observer:
            self._observer.stop()
            self._observer.join()
        if self._worker:
            self._worker.stop()
            self._worker.join(timeout=10)
        self._running = False
        logger.info("Daemon stopped")

    def retag_all(self):
        """Force re-tag all files in watch dir."""
        watch_dir = self.config["watch_dir"]
        supported = self.config["supported_extensions"]
        all_exts = {ext for exts in supported.values() for ext in exts}
        count = 0
        for p in Path(watch_dir).rglob("*"):
            if p.is_file() and not p.name.startswith(".") and p.suffix.lower() in all_exts:
                self._file_queue.put(str(p))
                count += 1
        logger.info(f"Queued {count} files for re-tagging")
        return count

    def retag_file(self, path: str):
        """Force re-tag a single file."""
        self._file_queue.put(path)
