"""FileTagger CLI entry point."""
import os
import sys
import signal
import logging
import json
import threading
from pathlib import Path
from typing import Optional

import typer
import uvicorn

from .config import load_config, save_config, init_config, CONFIG_PATH
from .db import init_db, search_files, all_tags, stats
from .tagger import check_ollama
from .daemon import Daemon
from .web import create_app

app = typer.Typer(name="filetagger", help="AI-powered file manager daemon.", add_completion=False)

PID_FILE = Path.home() / ".filetagger" / "filetagger.pid"


def setup_logging(level: str):
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
        datefmt="%H:%M:%S"
    )


@app.command()
def init(
    watch_dir: Optional[str] = typer.Option(None, "--watch-dir", "-w", help="Directory to watch"),
    ollama_url: Optional[str] = typer.Option(None, "--ollama-url", help="Ollama base URL"),
    ollama_model: Optional[str] = typer.Option(None, "--model", help="Ollama model name"),
):
    """Initialize FileTagger config and watch directory."""
    created = init_config()
    config = load_config()

    if watch_dir:
        config["watch_dir"] = str(Path(watch_dir).expanduser())
    if ollama_url:
        config["ollama_base_url"] = ollama_url
    if ollama_model:
        config["ollama_model"] = ollama_model

    save_config(config)
    Path(config["watch_dir"]).mkdir(parents=True, exist_ok=True)

    if created:
        typer.echo(f"✓ Created config: {CONFIG_PATH}")
    else:
        typer.echo(f"✓ Updated config: {CONFIG_PATH}")

    typer.echo(f"  Watch dir : {config['watch_dir']}")
    typer.echo(f"  Ollama URL: {config['ollama_base_url']}")
    typer.echo(f"  Model     : {config['ollama_model']}")

    ok, msg = check_ollama(config)
    if ok:
        typer.echo(f"  Ollama    : ✓ {msg}")
    else:
        typer.echo(f"  Ollama    : ✗ {msg}", err=True)


@app.command()
def start(
    ollama_url: Optional[str] = typer.Option(None, "--ollama-url", help="Ollama base URL"),
    ollama_model: Optional[str] = typer.Option(None, "--model", help="Ollama model"),
    watch_dir: Optional[str] = typer.Option(None, "--watch-dir", "-w", help="Directory to watch"),
    host: str = typer.Option("127.0.0.1", "--host", help="Web UI host"),
    port: int = typer.Option(7432, "--port", "-p", help="Web UI port"),
    no_web: bool = typer.Option(False, "--no-web", help="Disable web UI"),
    log_level: str = typer.Option("INFO", "--log-level"),
    foreground: bool = typer.Option(False, "--fg", help="Run in foreground (don't daemonize)"),
):
    """Start the FileTagger daemon and web UI."""
    setup_logging(log_level)
    init_config()
    config = load_config()

    if ollama_url:
        config["ollama_base_url"] = ollama_url
    if ollama_model:
        config["ollama_model"] = ollama_model
    if watch_dir:
        config["watch_dir"] = str(Path(watch_dir).expanduser())
    config["web_host"] = host
    config["web_port"] = port

    ok, msg = check_ollama(config)
    if not ok:
        typer.echo(f"⚠ Ollama warning: {msg}", err=True)
        typer.echo("  Starting anyway — files will be queued until Ollama is reachable.")

    daemon = Daemon(config)
    daemon.start()

    if not foreground:
        # Write PID
        PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(str(os.getpid()))

    typer.echo(f"✓ FileTagger daemon started")
    typer.echo(f"  Watching : {config['watch_dir']}")
    typer.echo(f"  Ollama   : {config['ollama_base_url']} ({config['ollama_model']})")

    def handle_stop(sig, frame):
        typer.echo("\nShutting down...")
        daemon.stop()
        if PID_FILE.exists():
            PID_FILE.unlink()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_stop)
    signal.signal(signal.SIGINT, handle_stop)

    if not no_web:
        typer.echo(f"  Web UI   : http://{host}:{port}")
        web_app = create_app(config, daemon)
        uvicorn.run(web_app, host=host, port=port,
                    log_level=log_level.lower(), access_log=False)
    else:
        typer.echo("  Web UI   : disabled (--no-web)")
        signal.pause()


@app.command()
def stop():
    """Stop a running FileTagger daemon."""
    if not PID_FILE.exists():
        typer.echo("No running daemon found (no PID file).")
        raise typer.Exit(1)
    pid = int(PID_FILE.read_text().strip())
    try:
        os.kill(pid, signal.SIGTERM)
        typer.echo(f"✓ Sent SIGTERM to PID {pid}")
        PID_FILE.unlink(missing_ok=True)
    except ProcessLookupError:
        typer.echo(f"PID {pid} not found, cleaning up.")
        PID_FILE.unlink(missing_ok=True)


@app.command()
def status():
    """Show daemon and Ollama status."""
    config = load_config()
    typer.echo(f"Config   : {CONFIG_PATH}")
    typer.echo(f"Watch dir: {config['watch_dir']}")
    typer.echo(f"Ollama   : {config['ollama_base_url']} / {config['ollama_model']}")
    typer.echo(f"Web UI   : http://{config['web_host']}:{config['web_port']}")

    ok, msg = check_ollama(config)
    typer.echo(f"Ollama   : {'✓' if ok else '✗'} {msg}")

    running = PID_FILE.exists()
    if running:
        pid = PID_FILE.read_text().strip()
        typer.echo(f"Daemon   : running (PID {pid})")
    else:
        typer.echo("Daemon   : not running")

    db_path = config["db_path"]
    if Path(db_path).exists():
        conn = init_db(db_path)
        s = stats(conn)
        typer.echo(f"\nDatabase:")
        typer.echo(f"  Total files : {s['total']}")
        typer.echo(f"  Errors      : {s['errors']}")
        typer.echo(f"  Untagged    : {s['untagged']}")
        for c in s["by_category"]:
            typer.echo(f"  {c['category']:12}: {c['count']}")


@app.command()
def search(
    query: Optional[str] = typer.Argument(None, help="Search query"),
    tag: Optional[str] = typer.Option(None, "--tag", "-t", help="Filter by tag"),
    category: Optional[str] = typer.Option(None, "--category", "-c", help="Filter by category"),
    limit: int = typer.Option(20, "--limit", "-n"),
    json_out: bool = typer.Option(False, "--json", help="Output as JSON"),
):
    """Search indexed files from the CLI."""
    config = load_config()
    if not Path(config["db_path"]).exists():
        typer.echo("No database found. Run 'filetagger start' first.", err=True)
        raise typer.Exit(1)

    conn = init_db(config["db_path"])
    tags = [tag] if tag else []
    results = search_files(conn, query=query or "", tags=tags,
                           category=category, limit=limit)

    if json_out:
        typer.echo(json.dumps(results, indent=2))
        return

    if not results:
        typer.echo("No results found.")
        return

    for f in results:
        tags_str = ", ".join(f["tags"][:5]) if f["tags"] else "no tags"
        typer.echo(f"\n{'─'*60}")
        typer.echo(f"  {f['filename']}")
        typer.echo(f"  {f['path']}")
        typer.echo(f"  Summary : {f['summary'] or 'none'}")
        typer.echo(f"  Tags    : {tags_str}")
        typer.echo(f"  Category: {f['category']}  Size: {(f['size_bytes'] or 0)//1024} KB")


@app.command()
def tags(
    limit: int = typer.Option(30, "--limit", "-n"),
):
    """List all tags and their file counts."""
    config = load_config()
    if not Path(config["db_path"]).exists():
        typer.echo("No database found.", err=True)
        raise typer.Exit(1)
    conn = init_db(config["db_path"])
    tag_list = all_tags(conn)[:limit]
    for t in tag_list:
        typer.echo(f"  {t['tag']:30} {t['count']} files")


@app.command()
def config(
    set_ollama_url: Optional[str] = typer.Option(None, "--ollama-url"),
    set_model: Optional[str] = typer.Option(None, "--model"),
    set_watch_dir: Optional[str] = typer.Option(None, "--watch-dir"),
    show: bool = typer.Option(False, "--show", help="Print current config"),
):
    """View or update configuration."""
    cfg = load_config()
    if set_ollama_url:
        cfg["ollama_base_url"] = set_ollama_url
    if set_model:
        cfg["ollama_model"] = set_model
    if set_watch_dir:
        cfg["watch_dir"] = str(Path(set_watch_dir).expanduser())

    if any([set_ollama_url, set_model, set_watch_dir]):
        save_config(cfg)
        typer.echo("✓ Config saved")

    if show or not any([set_ollama_url, set_model, set_watch_dir]):
        safe = {k: v for k, v in cfg.items() if k != "supported_extensions"}
        typer.echo(json.dumps(safe, indent=2))


def main():
    app()


if __name__ == "__main__":
    main()
