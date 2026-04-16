"""SQLite database layer with FTS5 full-text search."""
import sqlite3
import json
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Optional


def get_conn(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db(db_path: str):
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = get_conn(db_path)
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS files (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            path        TEXT UNIQUE NOT NULL,
            filename    TEXT NOT NULL,
            extension   TEXT,
            size_bytes  INTEGER,
            file_hash   TEXT,
            category    TEXT,
            summary     TEXT,
            tags        TEXT DEFAULT '[]',
            tagged_at   TEXT,
            modified_at TEXT,
            indexed_at  TEXT DEFAULT (datetime('now')),
            error       TEXT
        );

        CREATE TABLE IF NOT EXISTS tag_index (
            tag     TEXT NOT NULL,
            file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            PRIMARY KEY (tag, file_id)
        );

        CREATE INDEX IF NOT EXISTS idx_files_path      ON files(path);
        CREATE INDEX IF NOT EXISTS idx_files_category  ON files(category);
        CREATE INDEX IF NOT EXISTS idx_files_extension ON files(extension);
        CREATE INDEX IF NOT EXISTS idx_tag_index_tag   ON tag_index(tag);

        CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            filename, summary, tags, content=files, content_rowid=id
        );

        CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
            INSERT INTO files_fts(rowid, filename, summary, tags)
            VALUES (new.id, new.filename, new.summary, new.tags);
        END;

        CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, filename, summary, tags)
            VALUES ('delete', old.id, old.filename, old.summary, old.tags);
        END;

        CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, filename, summary, tags)
            VALUES ('delete', old.id, old.filename, old.summary, old.tags);
            INSERT INTO files_fts(rowid, filename, summary, tags)
            VALUES (new.id, new.filename, new.summary, new.tags);
        END;
    """)
    conn.commit()
    return conn


def file_hash(path: str) -> str:
    h = hashlib.md5()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return ""


def upsert_file(conn, path: str, category: str, summary: str, tags: list,
                size_bytes: int, fhash: str, error: str = None):
    tags_json = json.dumps(tags)
    now = datetime.now().isoformat()
    p = Path(path)
    conn.execute("""
        INSERT INTO files (path, filename, extension, size_bytes, file_hash,
                           category, summary, tags, tagged_at, modified_at, error)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            filename    = excluded.filename,
            extension   = excluded.extension,
            size_bytes  = excluded.size_bytes,
            file_hash   = excluded.file_hash,
            category    = excluded.category,
            summary     = excluded.summary,
            tags        = excluded.tags,
            tagged_at   = excluded.tagged_at,
            modified_at = excluded.modified_at,
            error       = excluded.error
    """, (path, p.name, p.suffix.lower(), size_bytes, fhash,
          category, summary, tags_json, now, now, error))
    file_id = conn.execute("SELECT id FROM files WHERE path=?", (path,)).fetchone()["id"]
    conn.execute("DELETE FROM tag_index WHERE file_id=?", (file_id,))
    conn.executemany("INSERT OR IGNORE INTO tag_index (tag, file_id) VALUES (?,?)",
                     [(t.lower(), file_id) for t in tags])
    conn.commit()


def remove_file(conn, path: str):
    conn.execute("DELETE FROM files WHERE path=?", (path,))
    conn.commit()


def get_file(conn, path: str) -> Optional[dict]:
    row = conn.execute("SELECT * FROM files WHERE path=?", (path,)).fetchone()
    return dict(row) if row else None


def needs_reindex(conn, path: str, fhash: str) -> bool:
    row = conn.execute("SELECT file_hash FROM files WHERE path=?", (path,)).fetchone()
    if not row:
        return True
    return row["file_hash"] != fhash


def search_files(conn, query: str = "", tags: list = None,
                 category: str = None, limit: int = 200) -> list:
    params = []
    conditions = []

    base = """
        SELECT f.id, f.path, f.filename, f.extension, f.category,
               f.summary, f.tags, f.tagged_at, f.size_bytes, f.error
        FROM files f
    """

    if query:
        base = """
            SELECT f.id, f.path, f.filename, f.extension, f.category,
                   f.summary, f.tags, f.tagged_at, f.size_bytes, f.error
            FROM files_fts fts
            JOIN files f ON fts.rowid = f.id
            WHERE files_fts MATCH ?
        """
        params.append(query)
    else:
        base += " WHERE 1=1"

    if tags:
        for tag in tags:
            conditions.append("""
                f.id IN (SELECT file_id FROM tag_index WHERE tag=?)
            """)
            params.append(tag.lower())

    if category:
        conditions.append("f.category=?")
        params.append(category)

    if conditions:
        connector = " AND " if query else " AND "
        base += connector + connector.join(conditions)

    base += f" ORDER BY f.tagged_at DESC LIMIT {limit}"
    rows = conn.execute(base, params).fetchall()
    result = []
    for row in rows:
        d = dict(row)
        try:
            d["tags"] = json.loads(d["tags"] or "[]")
        except Exception:
            d["tags"] = []
        result.append(d)
    return result


def all_tags(conn) -> list:
    rows = conn.execute("""
        SELECT tag, COUNT(*) as count FROM tag_index
        GROUP BY tag ORDER BY count DESC
    """).fetchall()
    return [{"tag": r["tag"], "count": r["count"]} for r in rows]


def stats(conn) -> dict:
    total = conn.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    by_cat = conn.execute("""
        SELECT category, COUNT(*) as count FROM files
        GROUP BY category ORDER BY count DESC
    """).fetchall()
    errors = conn.execute("SELECT COUNT(*) FROM files WHERE error IS NOT NULL").fetchone()[0]
    untagged = conn.execute("SELECT COUNT(*) FROM files WHERE tagged_at IS NULL").fetchone()[0]
    return {
        "total": total,
        "errors": errors,
        "untagged": untagged,
        "by_category": [dict(r) for r in by_cat]
    }