"""Configuration management for FileTagger."""
import os
import sys
import json
from pathlib import Path

DEFAULT_CONFIG = {
    "watch_dir": str(Path.home() / "Documents"),
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

# Sentinel — means "not set by user yet"
_UNSET = ""


def load_config(config_path: Path = None) -> dict:
    path = config_path or CONFIG_PATH
    config = DEFAULT_CONFIG.copy()
    if path.exists():
        with open(path) as f:
            user_config = json.load(f)
        config.update(user_config)
    # Environment variable overrides (highest priority)
    if url := os.environ.get("FILETAGGER_OLLAMA_URL"):
        config["ollama_base_url"] = url
    if model := os.environ.get("FILETAGGER_OLLAMA_MODEL"):
        config["ollama_model"] = model
    if watch := os.environ.get("FILETAGGER_WATCH_DIR"):
        config["watch_dir"] = watch
    return config


def save_config(config: dict, config_path: Path = None):
    path = config_path or CONFIG_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(config, f, indent=2)


def _is_interactive() -> bool:
    """Return True if we're attached to a real terminal."""
    return sys.stdin.isatty() and sys.stdout.isatty()


def _prompt(label: str, default: str = "", required: bool = False) -> str:
    """Prompt user for input, showing default in brackets."""
    if default:
        prompt_str = f"  {label} [{default}]: "
    else:
        prompt_str = f"  {label}: "

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
    """
    Interactively prompt the user to configure Ollama on first run.
    Falls back gracefully if not in a terminal (systemd service, CI, etc).
    Env vars always win — if they're already set, skip prompting.
    """
    ollama_url = config.get("ollama_base_url", "")
    ollama_model = config.get("ollama_model", "")
    watch_dir = config.get("watch_dir", str(Path.home() / "Documents"))

    # If env vars provided everything, nothing to do
    env_url = os.environ.get("FILETAGGER_OLLAMA_URL", "")
    env_model = os.environ.get("FILETAGGER_OLLAMA_MODEL", "")
    if env_url and env_model:
        return config

    # If not interactive (systemd service), use fallback defaults and warn
    if not _is_interactive():
        if not ollama_url:
            config["ollama_base_url"] = "http://localhost:11434"
        if not ollama_model:
            config["ollama_model"] = "llama3.2"
        return config

    # Interactive setup
    _print_banner()

    print("  ── Ollama Connection ─────────────────────────────")
    new_url = _prompt(
        "Ollama base URL",
        default=ollama_url or "http://localhost:11434",
        required=True,
    )

    print()
    print("  ── Ollama Model ──────────────────────────────────")
    print("  Tip: run 'ollama list' on your server to see available models.")
    new_model = _prompt(
        "Model name",
        default=ollama_model or "llama3.2",
        required=True,
    )

    print()
    print("  ── Watch Directory ───────────────────────────────")
    print("  FileTagger will monitor this folder and all subfolders.")
    new_watch = _prompt(
        "Directory to watch",
        default=watch_dir,
        required=True,
    )

    # Expand ~ in watch dir
    new_watch = str(Path(new_watch).expanduser())

    config["ollama_base_url"] = new_url
    config["ollama_model"] = new_model
    config["watch_dir"] = new_watch

    print()
    print("  ✓ Configuration saved to ~/.filetagger/config.json")
    print()

    return config


def needs_first_run_setup(config: dict) -> bool:
    """
    Return True if essential config values are missing and not
    covered by environment variables.
    """
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
    """
    Create config file if it doesn't exist, prompt for essentials on first run.
    Returns (config, is_new) tuple.
    """
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)

    is_new = not CONFIG_PATH.exists()

    if is_new:
        save_config(DEFAULT_CONFIG)

    config = load_config()

    if not skip_prompt and needs_first_run_setup(config):
        config = first_run_setup(config)
        save_config(config)

    # Ensure watch dir exists
    watch_dir = Path(config["watch_dir"])
    watch_dir.mkdir(parents=True, exist_ok=True)

    return config, is_new