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
from .config import load_config, save_config
from .tagger import check_ollama

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
            "watch_dir": _config["watch_dir"],
            "ollama_url": _config["ollama_base_url"],
            "ollama_model": _config["ollama_model"],
            "ollama_ok": ollama_ok,
            "ollama_msg": ollama_msg,
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
        watch_dir: Optional[str] = None
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
