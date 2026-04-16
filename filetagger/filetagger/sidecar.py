"""
Write TagSpaces-compatible sidecar files alongside tagged files.

TagSpaces stores metadata in a hidden .ts/ folder next to each file:
  ~/files/
    report.pdf
    .ts/
      report.pdf.json   ← this is what we write

Sidecar format (TagSpaces 6.x):
{
  "appName": "TagSpaces",
  "appVersion": "6.0.0",
  "lastUpdated": "2024-01-01T00:00:00.000Z",
  "tags": [
    { "title": "finance", "type": "sidecar" },
    ...
  ],
  "description": "One-sentence summary from Ollama"
}
"""

import json
import logging
from pathlib import Path
from datetime import datetime, timezone

logger = logging.getLogger("filetagger.sidecar")

TAGSPACES_APP_NAME = "TagSpaces"
TAGSPACES_APP_VERSION = "6.0.0"


def sidecar_dir(file_path: str) -> Path:
    """Return the .ts/ directory for a given file's parent."""
    return Path(file_path).parent / ".ts"


def sidecar_path(file_path: str) -> Path:
    """Return the full path to the sidecar JSON for a given file."""
    p = Path(file_path)
    return sidecar_dir(file_path) / f"{p.name}.json"


def write_sidecar(file_path: str, tags: list, description: str = ""):
    """
    Write a TagSpaces sidecar JSON file for the given file.
    Creates the .ts/ directory if it doesn't exist.
    Merges with existing sidecar tags if present (preserves manual user tags).
    """
    sc_path = sidecar_path(file_path)
    sc_dir = sidecar_dir(file_path)

    try:
        sc_dir.mkdir(exist_ok=True)

        # Load existing sidecar if present, to preserve manually added tags
        existing_tags = []
        if sc_path.exists():
            try:
                existing = json.loads(sc_path.read_text())
                existing_tags = existing.get("tags", [])
            except Exception:
                pass

        # Keep any existing tags that were added manually (type != "sidecar")
        # Replace all "sidecar" type tags with our new AI-generated set
        manual_tags = [t for t in existing_tags if t.get("type") != "sidecar"]
        ai_tags = [{"title": t.lower(), "type": "sidecar"} for t in tags]

        # Deduplicate: if a manual tag matches an AI tag title, keep manual
        manual_titles = {t["title"] for t in manual_tags}
        merged_tags = manual_tags + [t for t in ai_tags if t["title"] not in manual_titles]

        sidecar = {
            "appName": TAGSPACES_APP_NAME,
            "appVersion": TAGSPACES_APP_VERSION,
            "lastUpdated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
            "tags": merged_tags,
            "description": description or "",
        }

        sc_path.write_text(json.dumps(sidecar, indent=2, ensure_ascii=False))
        logger.debug(f"Sidecar written: {sc_path}")

    except Exception as e:
        logger.warning(f"Failed to write sidecar for {file_path}: {e}")


def read_sidecar(file_path: str) -> dict:
    """Read existing sidecar for a file. Returns empty dict if none."""
    sc_path = sidecar_path(file_path)
    if not sc_path.exists():
        return {}
    try:
        return json.loads(sc_path.read_text())
    except Exception:
        return {}


def delete_sidecar(file_path: str):
    """Remove the sidecar file for a deleted/moved file."""
    sc_path = sidecar_path(file_path)
    try:
        if sc_path.exists():
            sc_path.unlink()
            # Clean up .ts dir if empty
            sc_dir = sidecar_dir(file_path)
            if sc_dir.exists() and not any(sc_dir.iterdir()):
                sc_dir.rmdir()
    except Exception as e:
        logger.warning(f"Failed to delete sidecar for {file_path}: {e}")