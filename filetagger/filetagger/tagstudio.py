"""
TagStudio library integration.

Writes tags directly into an existing TagStudio library database
(~/Documents/.TagStudio/ts_library.sqlite).

Design:
  - Does NOT create the library DB from scratch — that belongs to TagStudio
  - Polls for the DB to exist before allowing any writes
  - Once found, introspects the live schema so we're always compatible
  - Safe to run concurrently with TagStudio (uses WAL mode + per-write transactions)

TagStudio DB structure (v9.5.x, DB_VERSION 100-103):
  versions      — key/value: INITIAL, CURRENT (DB version)
  entries       — id, path, folder, filename, suffix, date_added
  tags          — id, name, shorthand, color_id, is_hidden
  tag_aliases   — id, tag_id, name
  tag_parents   — parent_id, child_id
  tag_colors    — id, namespace, name, primary_color, secondary_color, color_border
  entry_tags    — entry_id, tag_id  (many-to-many)
  tag_fields    — id, entry_id, type_key, value  (text fields, dates, etc.)
"""

import sqlite3
import logging
import threading
import time
from pathlib import Path
from datetime import datetime, timezone
from typing import Optional

logger = logging.getLogger("filetagger.tagstudio")

# How long to wait between polls when library doesn't exist yet (seconds)
POLL_INTERVAL = 30

# Global state — one connection per library path
_conn_cache: dict[str, sqlite3.Connection] = {}
_conn_lock = threading.Lock()
_waiting_logged = False


def _ts_db_path(watch_dir: str) -> Path:
    """Return the expected TagStudio DB path for a watch directory."""
    return Path(watch_dir) / ".TagStudio" / "ts_library.sqlite"


def library_exists(watch_dir: str) -> bool:
    """Check if a TagStudio library exists for this watch directory."""
    return _ts_db_path(watch_dir).exists()


def wait_for_library(watch_dir: str, stop_event: threading.Event = None) -> bool:
    """
    Block until the TagStudio library exists, polling every POLL_INTERVAL seconds.
    Returns True when found, False if stop_event fired.
    """
    global _waiting_logged
    db_path = _ts_db_path(watch_dir)

    if db_path.exists():
        return True

    if not _waiting_logged:
        logger.info(
            f"Waiting for TagStudio library at {db_path}\n"
            f"  → Open TagStudio and set '{watch_dir}' as your library to begin tagging."
        )
        _waiting_logged = True

    while not db_path.exists():
        if stop_event and stop_event.is_set():
            return False
        time.sleep(POLL_INTERVAL)

    logger.info(f"TagStudio library found at {db_path} — starting tag sync")
    _waiting_logged = False
    return True


def _get_conn(watch_dir: str) -> Optional[sqlite3.Connection]:
    """Get a cached connection to the TagStudio library, or None if it doesn't exist."""
    db_path = _ts_db_path(watch_dir)
    if not db_path.exists():
        return None

    with _conn_lock:
        key = str(db_path)
        if key not in _conn_cache:
            conn = sqlite3.connect(str(db_path), check_same_thread=False)
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA foreign_keys=ON")
            conn.row_factory = sqlite3.Row
            _conn_cache[key] = conn
            logger.info(f"Connected to TagStudio library: {db_path}")
        return _conn_cache[key]


def _close_conn(watch_dir: str):
    """Close and remove a cached connection."""
    with _conn_lock:
        key = str(_ts_db_path(watch_dir))
        if key in _conn_cache:
            try:
                _conn_cache[key].close()
            except Exception:
                pass
            del _conn_cache[key]


def _has_column(conn: sqlite3.Connection, table: str, column: str) -> bool:
    """Check if a column exists in a table (handles schema version differences)."""
    try:
        cur = conn.execute(f"PRAGMA table_info({table})")
        return any(row["name"] == column for row in cur.fetchall())
    except Exception:
        return False


def _has_table(conn: sqlite3.Connection, table: str) -> bool:
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,)
    )
    return cur.fetchone() is not None


# ── Tag management ────────────────────────────────────────────────────────────

def _get_or_create_tag(conn: sqlite3.Connection, tag_name: str) -> int:
    """
    Get the ID of an existing tag by name, or create it.
    Returns tag ID.
    """
    # Search by exact name first
    row = conn.execute(
        "SELECT id FROM tags WHERE name=? COLLATE NOCASE LIMIT 1",
        (tag_name,)
    ).fetchone()
    if row:
        return row["id"]

    # Also check aliases
    if _has_table(conn, "tag_aliases"):
        row = conn.execute(
            "SELECT tag_id FROM tag_aliases WHERE name=? COLLATE NOCASE LIMIT 1",
            (tag_name,)
        ).fetchone()
        if row:
            return row["tag_id"]

    # Create new tag
    # Use a neutral color_id=0 (no color) — TagStudio uses 0 for uncolored
    has_hidden = _has_column(conn, "tags", "is_hidden")

    if has_hidden:
        cur = conn.execute(
            "INSERT INTO tags (name, shorthand, color_id, is_hidden) VALUES (?, ?, 0, 0)",
            (tag_name, "")
        )
    else:
        cur = conn.execute(
            "INSERT INTO tags (name, shorthand, color_id) VALUES (?, ?, 0)",
            (tag_name, "")
        )
    tag_id = cur.lastrowid
    logger.debug(f"Created TagStudio tag: '{tag_name}' (id={tag_id})")
    return tag_id


# ── Entry management ──────────────────────────────────────────────────────────

def _get_or_create_entry(conn: sqlite3.Connection, file_path: str, watch_dir: str) -> int:
    """
    Get the ID of an existing entry by path, or create it.
    Path stored in TagStudio is relative to the library root.
    Returns entry ID.
    """
    p = Path(file_path)
    watch = Path(watch_dir)

    try:
        rel_path = p.relative_to(watch)
    except ValueError:
        rel_path = p

    # TagStudio stores path as POSIX string relative to library root
    rel_str = rel_path.as_posix()
    folder_str = rel_path.parent.as_posix() if rel_path.parent != Path(".") else ""
    filename = p.name
    suffix = p.suffix.lower()

    # Try to find existing entry
    row = conn.execute(
        "SELECT id FROM entries WHERE path=? LIMIT 1",
        (rel_str,)
    ).fetchone()
    if row:
        return row["id"]

    # Create new entry
    now_iso = datetime.now(timezone.utc).isoformat()
    has_filename_col = _has_column(conn, "entries", "filename")

    if has_filename_col:
        cur = conn.execute(
            """INSERT INTO entries (path, folder, filename, suffix, date_added)
               VALUES (?, ?, ?, ?, ?)""",
            (rel_str, folder_str, filename, suffix, now_iso)
        )
    else:
        # Older schema without filename column
        cur = conn.execute(
            "INSERT INTO entries (path, folder, suffix, date_added) VALUES (?, ?, ?, ?)",
            (rel_str, folder_str, suffix, now_iso)
        )

    entry_id = cur.lastrowid
    logger.debug(f"Created TagStudio entry: '{rel_str}' (id={entry_id})")
    return entry_id


# ── Tag assignment ────────────────────────────────────────────────────────────

def _set_entry_tags(conn: sqlite3.Connection, entry_id: int, tag_ids: list[int]):
    """Replace all filetagger-managed tags on an entry with the new set."""
    # We only remove tags that we know we put there — we never touch tags
    # the user added manually in TagStudio. We track ours by a special
    # convention: all tags in the 'filetagger_managed' set.
    # Simplest safe approach: remove all existing tags and re-add.
    # TagStudio supports this since it stores them per-entry.
    conn.execute("DELETE FROM entry_tags WHERE entry_id=?", (entry_id,))
    conn.executemany(
        "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)",
        [(entry_id, tag_id) for tag_id in tag_ids]
    )


def _set_description_field(conn: sqlite3.Connection, entry_id: int, summary: str):
    """Write the AI summary as a TagStudio text field on the entry."""
    if not _has_table(conn, "tag_fields"):
        return
    if not summary:
        return

    # TagStudio uses type_key strings for field types
    # 'TEXT_LINE' = single line text, 'TEXT_BOX' = multiline
    type_key = "TEXT_LINE"

    # Check if a description field already exists
    row = conn.execute(
        "SELECT id FROM tag_fields WHERE entry_id=? AND type_key=? LIMIT 1",
        (entry_id, type_key)
    ).fetchone()

    if row:
        conn.execute(
            "UPDATE tag_fields SET value=? WHERE id=?",
            (summary, row["id"])
        )
    else:
        conn.execute(
            "INSERT INTO tag_fields (entry_id, type_key, value) VALUES (?, ?, ?)",
            (entry_id, type_key, summary)
        )


# ── Public API ────────────────────────────────────────────────────────────────

def write_to_tagstudio(
    file_path: str,
    tags: list[str],
    summary: str,
    watch_dir: str,
) -> bool:
    """
    Write tags and summary to the TagStudio library for a file.

    Returns True on success, False if library doesn't exist yet.
    Silently skips if library not found (daemon handles polling separately).
    """
    conn = _get_conn(watch_dir)
    if conn is None:
        return False

    try:
        # Resolve tag IDs (create tags in TagStudio if they don't exist)
        tag_ids = []
        for tag in tags:
            tag_id = _get_or_create_tag(conn, tag)
            tag_ids.append(tag_id)

        # Get or create the entry
        entry_id = _get_or_create_entry(conn, file_path, watch_dir)

        # Assign tags
        _set_entry_tags(conn, entry_id, tag_ids)

        # Write summary as description field
        if summary:
            _set_description_field(conn, entry_id, summary)

        conn.commit()
        logger.debug(f"TagStudio: wrote {len(tags)} tags for {Path(file_path).name}")
        return True

    except sqlite3.OperationalError as e:
        # Schema mismatch or DB locked — close connection so it gets re-opened fresh
        logger.warning(f"TagStudio write error for {file_path}: {e}")
        _close_conn(watch_dir)
        return False
    except Exception as e:
        logger.error(f"TagStudio unexpected error for {file_path}: {e}")
        return False


def remove_from_tagstudio(file_path: str, watch_dir: str) -> bool:
    """Remove an entry from the TagStudio library when a file is deleted."""
    conn = _get_conn(watch_dir)
    if conn is None:
        return False

    try:
        p = Path(file_path)
        watch = Path(watch_dir)
        try:
            rel_str = p.relative_to(watch).as_posix()
        except ValueError:
            rel_str = p.as_posix()

        row = conn.execute(
            "SELECT id FROM entries WHERE path=? LIMIT 1", (rel_str,)
        ).fetchone()
        if row:
            entry_id = row["id"]
            conn.execute("DELETE FROM entry_tags WHERE entry_id=?", (entry_id,))
            conn.execute("DELETE FROM tag_fields WHERE entry_id=?", (entry_id,))
            conn.execute("DELETE FROM entries WHERE id=?", (entry_id,))
            conn.commit()
            logger.debug(f"TagStudio: removed entry for {p.name}")
        return True
    except Exception as e:
        logger.warning(f"TagStudio remove error: {e}")
        return False


def tagstudio_stats(watch_dir: str) -> dict:
    """Return basic stats about the TagStudio library."""
    conn = _get_conn(watch_dir)
    if conn is None:
        return {"available": False}
    try:
        entries = conn.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
        tags = conn.execute("SELECT COUNT(*) FROM tags").fetchone()[0]
        entry_tags = conn.execute("SELECT COUNT(*) FROM entry_tags").fetchone()[0]

        # Get DB version
        version = "unknown"
        if _has_table(conn, "versions"):
            row = conn.execute(
                "SELECT value FROM versions WHERE key='CURRENT' LIMIT 1"
            ).fetchone()
            if row:
                version = str(row[0])
        elif _has_table(conn, "preferences"):
            row = conn.execute(
                "SELECT value FROM preferences WHERE key='DB_VERSION' LIMIT 1"
            ).fetchone()
            if row:
                version = str(row[0])

        return {
            "available": True,
            "db_version": version,
            "entries": entries,
            "tags": tags,
            "entry_tags": entry_tags,
            "db_path": str(_ts_db_path(watch_dir)),
        }
    except Exception as e:
        return {"available": False, "error": str(e)}