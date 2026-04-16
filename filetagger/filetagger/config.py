"""Configuration management for FileTagger."""
import os
import json
from pathlib import Path

DEFAULT_CONFIG = {
    "watch_dir": str(Path.home() / "files"),
    "db_path": str(Path.home() / ".filetagger" / "filetagger.db"),
    "ollama_base_url": "http://localhost:11434",
    "ollama_model": "gpt-oss:20b-cloud",
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
    if path.exists():
        with open(path) as f:
            user_config = json.load(f)
        config.update(user_config)
    # Environment variable overrides
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


def init_config():
    """Create default config and watch dir if they don't exist."""
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    watch_dir = Path(DEFAULT_CONFIG["watch_dir"])
    watch_dir.mkdir(parents=True, exist_ok=True)
    if not CONFIG_PATH.exists():
        save_config(DEFAULT_CONFIG)
        return True
    return False
