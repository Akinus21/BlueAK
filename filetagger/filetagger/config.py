"""Configuration management for FileTagger."""
import os
import sys
import json
from pathlib import Path

DEFAULT_CONFIG = {
    "watch_dirs": [str(Path.home() / "Documents")],
    "db_path": str(Path.home() / ".filetagger" / "filetagger.db"),
    "ollama_base_url": "",
    "ollama_model": "",
    "web_host": "127.0.0.1",
    "web_port": 7432,
    "log_level": "INFO",
    "supported_extensions": {
        "documents": [".pdf", ".doc", ".docx", ".odt", ".txt", ".md", ".rtf", ".csv", ".xlsx", ".xls", ".pptx", ".ppt"],
        "images": [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp", ".svg"],
        "code": [".py", ".js", ".ts", ".sh", ".bash", ".c", ".cpp", ".h", ".java", ".go", ".rs", ".rb", ".php", ".yaml", ".yml", ".json", ".toml", ".ini", ".conf"],
        "audio": [".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac"],
        "video": [".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv"]
    },
    "max_content_chars": 4000,
    "retag_on_modify": True,
    "ocr_enabled": True,
    "whisper_enabled": False,
}

CONFIG_PATH = Path.home() / ".filetagger" / "config.json"


def load_config(config_path: Path = None) -> dict:
    path = config_path or CONFIG_PATH
    config = DEFAULT_CONFIG.copy()
    config["watch_dirs"] = list(DEFAULT_CONFIG["watch_dirs"])

    if path.exists():
        with open(path) as f:
            user_config = json.load(f)

        # Migrate legacy single watch_dir to watch_dirs list
        if "watch_dir" in user_config and "watch_dirs" not in user_config:
            user_config["watch_dirs"] = [user_config.pop("watch_dir")]
        elif "watch_dir" in user_config:
            user_config.pop("watch_dir")

        config.update(user_config)

    # Environment variable overrides (highest priority)
    if url := os.environ.get("FILETAGGER_OLLAMA_URL"):
        config["ollama_base_url"] = url
    if model := os.environ.get("FILETAGGER_OLLAMA_MODEL"):
        config["ollama_model"] = model

    # FILETAGGER_WATCH_DIRS — colon-separated list like PATH
    if dirs := os.environ.get("FILETAGGER_WATCH_DIRS"):
        config["watch_dirs"] = [d for d in dirs.split(":") if d.strip()]
    # Legacy single var still supported
    elif watch := os.environ.get("FILETAGGER_WATCH_DIR"):
        if watch not in config["watch_dirs"]:
            config["watch_dirs"] = [watch]

    # Deduplicate and expand ~
    config["watch_dirs"] = list(dict.fromkeys(
        str(Path(d).expanduser()) for d in config["watch_dirs"] if d
    ))

    return config


def save_config(config: dict, config_path: Path = None):
    path = config_path or CONFIG_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    # Never save legacy watch_dir key
    save = {k: v for k, v in config.items() if k != "watch_dir"}
    with open(path, "w") as f:
        json.dump(save, f, indent=2)


def add_watch_dir(directory: str, config: dict = None) -> dict:
    """Add a directory to the watch list. Saves config."""
    cfg = config or load_config()
    expanded = str(Path(directory).expanduser().resolve())
    if expanded not in cfg["watch_dirs"]:
        cfg["watch_dirs"].append(expanded)
        save_config(cfg)
    return cfg


def remove_watch_dir(directory: str, config: dict = None) -> dict:
    """Remove a directory from the watch list. Saves config."""
    cfg = config or load_config()
    expanded = str(Path(directory).expanduser().resolve())
    cfg["watch_dirs"] = [d for d in cfg["watch_dirs"] if d != expanded]
    if not cfg["watch_dirs"]:
        cfg["watch_dirs"] = [str(Path.home() / "Documents")]
    save_config(cfg)
    return cfg


def _is_interactive() -> bool:
    return sys.stdin.isatty() and sys.stdout.isatty()


def _prompt(label: str, default: str = "", required: bool = False) -> str:
    prompt_str = f"  {label} [{default}]: " if default else f"  {label}: "
    while True:
        try:
            value = input(prompt_str).strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return default
        if value:
            return value
        if default:
            return default
        if not required:
            return ""
        print(f"  ✗ {label} is required.")


def _print_banner():
    print()
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║          FileTagger — First Run Setup        ║")
    print("  ╚══════════════════════════════════════════════╝")
    print()
    print("  FileTagger needs to know where your Ollama instance")
    print("  is running to generate AI tags for your files.")
    print()
    print("  You can change these settings at any time:")
    print("    • CLI:    filetagger config --ollama-url <url>")
    print("    • Web UI: http://localhost:7432  → ⚙ Settings")
    print("    • File:   ~/.filetagger/config.json")
    print()


def first_run_setup(config: dict) -> dict:
    """Interactively prompt for Ollama config on first run."""
    ollama_url   = config.get("ollama_base_url", "")
    ollama_model = config.get("ollama_model", "")
    watch_dirs   = config.get("watch_dirs", [str(Path.home() / "Documents")])

    env_url   = os.environ.get("FILETAGGER_OLLAMA_URL", "")
    env_model = os.environ.get("FILETAGGER_OLLAMA_MODEL", "")
    if env_url and env_model:
        return config

    if not _is_interactive():
        if not ollama_url:
            config["ollama_base_url"] = "http://localhost:11434"
        if not ollama_model:
            config["ollama_model"] = "llama3.2"
        return config

    _print_banner()

    print("  ── Ollama Connection ─────────────────────────────")
    new_url = _prompt("Ollama base URL",
                      default=ollama_url or "http://localhost:11434",
                      required=True)

    print()
    print("  ── Ollama Model ──────────────────────────────────")
    print("  Tip: run 'ollama list' on your server to see available models.")
    new_model = _prompt("Model name",
                        default=ollama_model or "llama3.2",
                        required=True)

    print()
    print("  ── Watch Directories ─────────────────────────────")
    print("  FileTagger will monitor these folders and all subfolders.")
    print("  Enter one directory per line. Leave blank to finish.")
    print(f"  Current: {', '.join(watch_dirs) or 'none'}")
    print()

    new_dirs = []
    idx = 1
    while True:
        d = _prompt(f"Directory {idx}", default="" if idx > 1 else watch_dirs[0] if watch_dirs else str(Path.home() / "Documents"))
        if not d:
            break
        new_dirs.append(str(Path(d).expanduser()))
        idx += 1

    if not new_dirs:
        new_dirs = watch_dirs or [str(Path.home() / "Documents")]

    config["ollama_base_url"] = new_url
    config["ollama_model"]    = new_model
    config["watch_dirs"]      = new_dirs

    print()
    print("  ✓ Configuration saved to ~/.filetagger/config.json")
    print()
    return config


def needs_first_run_setup(config: dict) -> bool:
    has_url = (
        config.get("ollama_base_url", "").strip()
        or os.environ.get("FILETAGGER_OLLAMA_URL", "").strip()
    )
    has_model = (
        config.get("ollama_model", "").strip()
        or os.environ.get("FILETAGGER_OLLAMA_MODEL", "").strip()
    )
    return not (has_url and has_model)


def init_config(skip_prompt: bool = False):
    """Create config if needed, prompt for essentials. Returns (config, is_new)."""
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    is_new = not CONFIG_PATH.exists()
    if is_new:
        save_config(DEFAULT_CONFIG)

    config = load_config()

    if not skip_prompt and needs_first_run_setup(config):
        config = first_run_setup(config)
        save_config(config)

    # Ensure all watch dirs exist
    for d in config["watch_dirs"]:
        Path(d).mkdir(parents=True, exist_ok=True)

    return config, is_new