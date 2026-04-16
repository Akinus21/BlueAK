"""FastAPI web server: REST API + WebUI."""
import json
import logging
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from .db import get_conn, init_db, search_files, all_tags, stats
from .config import load_config, save_config, add_watch_dir, remove_watch_dir
from .tagger import check_ollama
from .taxonomy import (
    load_taxonomy, save_taxonomy, load_pending,
    add_approved_tag, remove_approved_tag, add_alias,
    approve_pending_tag, reject_pending_tag, merge_pending_tag,
    pending_count, approved_tags, init_taxonomy
)

logger = logging.getLogger("filetagger.web")

# Will be set by the server startup
_config = None
_conn = None
_daemon = None


def create_app(config: dict, daemon=None):
    global _config, _conn, _daemon
    _config = config
    _conn = init_db(config["db_path"])
    _daemon = daemon

    app = FastAPI(title="FileTagger", version="0.1.0")

    # --- API Routes ---

    @app.get("/api/status")
    def get_status():
        ollama_ok, ollama_msg = check_ollama(_config)
        daemon_stats = _daemon.worker_stats if _daemon else {}
        return {
            "daemon_running": _daemon.is_running if _daemon else False,
            "watch_dirs": _config.get("watch_dirs", []),
            "ollama_url": _config["ollama_base_url"],
            "ollama_model": _config["ollama_model"],
            "ollama_ok": ollama_ok,
            "ollama_msg": ollama_msg,
            "pending_count": pending_count(),
            **daemon_stats
        }

    @app.get("/api/files")
    def get_files(
        q: Optional[str] = Query(None),
        tag: Optional[str] = Query(None),
        category: Optional[str] = Query(None),
        limit: int = Query(200, le=500)
    ):
        tags = [tag] if tag else []
        results = search_files(_conn, query=q or "", tags=tags,
                               category=category, limit=limit)
        return {"files": results, "count": len(results)}

    @app.get("/api/tags")
    def get_tags():
        return {"tags": all_tags(_conn)}

    @app.get("/api/stats")
    def get_stats():
        return stats(_conn)

    @app.get("/api/categories")
    def get_categories():
        return {"categories": list(_config["supported_extensions"].keys())}

    class ConfigUpdate(BaseModel):
        ollama_base_url: Optional[str] = None
        ollama_model: Optional[str] = None
        watch_dirs: Optional[list] = None
        ocr_enabled: Optional[bool] = None
        whisper_enabled: Optional[bool] = None
        retag_on_modify: Optional[bool] = None

    @app.get("/api/config")
    def get_config():
        safe = {k: v for k, v in _config.items()
                if k != "supported_extensions"}
        return safe

    @app.post("/api/config")
    def update_config(update: ConfigUpdate):
        global _config
        changed = update.dict(exclude_none=True)
        _config.update(changed)
        save_config(_config)
        return {"ok": True, "config": {k: v for k, v in _config.items()
                                        if k != "supported_extensions"}}

    @app.post("/api/retag-all")
    def retag_all():
        if not _daemon:
            raise HTTPException(503, "Daemon not running")
        count = _daemon.retag_all()
        return {"queued": count}

    @app.post("/api/retag/{file_id}")
    def retag_file(file_id: int):
        if not _daemon:
            raise HTTPException(503, "Daemon not running")
        from .db import get_conn as gc
        conn = gc(_config["db_path"])
        row = conn.execute("SELECT path FROM files WHERE id=?", (file_id,)).fetchone()
        if not row:
            raise HTTPException(404, "File not found")
        _daemon.retag_file(row["path"])
        return {"queued": row["path"]}

    @app.get("/api/open/{file_id}")
    def open_file(file_id: int):
        """Open a file with the system's default application."""
        import subprocess
        from .db import get_conn as gc
        conn = gc(_config["db_path"])
        row = conn.execute("SELECT path FROM files WHERE id=?", (file_id,)).fetchone()
        if not row:
            raise HTTPException(404, "File not found")
        path = row["path"]
        if not Path(path).exists():
            raise HTTPException(404, "File not found on disk")
        subprocess.Popen(["xdg-open", path])
        return {"ok": True}

    # --- Watch Dirs API ---

    class DirBody(BaseModel):
        directory: str

    @app.post("/api/watch-dirs")
    def add_dir(body: DirBody):
        global _config
        _config = add_watch_dir(body.directory, _config)
        return {"ok": True, "watch_dirs": _config["watch_dirs"]}

    @app.delete("/api/watch-dirs")
    def remove_dir(body: DirBody):
        global _config
        _config = remove_watch_dir(body.directory, _config)
        return {"ok": True, "watch_dirs": _config["watch_dirs"]}

    @app.get("/api/watch-dirs")
    def get_watch_dirs():
        from .tagstudio import library_exists
        dirs = _config.get("watch_dirs", [])
        return {
            "watch_dirs": [
                {
                    "path": d,
                    "tagstudio_ready": library_exists(d),
                }
                for d in dirs
            ]
        }

    # --- Taxonomy API ---

    @app.get("/api/taxonomy")
    def get_taxonomy():
        init_taxonomy()
        tax = load_taxonomy()
        by_category = {}
        for tag, meta in sorted(tax.items()):
            cat = meta.get("category", "misc")
            by_category.setdefault(cat, []).append({
                "tag": tag,
                "aliases": meta.get("aliases", []),
                "category": cat,
                "added_at": meta.get("added_at", ""),
            })
        return {"taxonomy": tax, "by_category": by_category, "total": len(tax)}

    class NewTag(BaseModel):
        tag: str
        category: str = ""
        aliases: list = []

    @app.post("/api/taxonomy")
    def create_tag(body: NewTag):
        add_approved_tag(body.tag, category=body.category, aliases=body.aliases)
        return {"ok": True, "tag": body.tag.lower()}

    @app.delete("/api/taxonomy/{tag}")
    def delete_tag(tag: str):
        remove_approved_tag(tag)
        return {"ok": True}

    class AliasBody(BaseModel):
        alias: str

    @app.post("/api/taxonomy/{tag}/alias")
    def add_tag_alias(tag: str, body: AliasBody):
        add_alias(tag, body.alias)
        return {"ok": True}

    @app.get("/api/pending")
    def get_pending():
        pending = load_pending()
        items = []
        for tag, meta in sorted(pending.items(),
                                 key=lambda x: x[1].get("file_count", 0), reverse=True):
            items.append({"tag": tag, **meta})
        return {"pending": items, "count": len(items)}

    class PendingAction(BaseModel):
        action: str          # "approve" | "reject" | "merge"
        category: str = ""
        merge_into: str = ""

    @app.post("/api/pending/{tag}")
    def handle_pending(tag: str, body: PendingAction):
        if body.action == "approve":
            ok = approve_pending_tag(tag, category=body.category)
        elif body.action == "reject":
            ok = reject_pending_tag(tag)
        elif body.action == "merge":
            if not body.merge_into:
                raise HTTPException(400, "merge_into required")
            ok = merge_pending_tag(tag, body.merge_into)
        else:
            raise HTTPException(400, f"Unknown action: {body.action}")
        return {"ok": ok}

    @app.post("/api/pending/approve-all")
    def approve_all_pending():
        pending = load_pending()
        count = 0
        for tag in list(pending.keys()):
            approve_pending_tag(tag)
            count += 1
        return {"approved": count}

    @app.post("/api/pending/reject-all")
    def reject_all_pending():
        pending = load_pending()
        count = len(pending)
        for tag in list(pending.keys()):
            reject_pending_tag(tag)
        return {"rejected": count}

    # --- Web UI ---
    @app.get("/", response_class=HTMLResponse)
    def index():
        return HTMLResponse(content=_get_ui_html())

    return app


def _get_ui_html() -> str:
    """Return the single-file web UI."""
    ui_path = Path(__file__).parent / "ui.html"
    if ui_path.exists():
        return ui_path.read_text()
    return "<h1>UI not found</h1>"