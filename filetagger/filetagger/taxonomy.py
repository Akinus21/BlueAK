"""
Tag taxonomy management.

Maintains two stores:
  ~/.filetagger/tags.json     — approved tag library (user-curated)
  ~/.filetagger/pending.json  — AI-proposed tags awaiting approval

Approved tags are the only ones written to sidecars/TagStudio.
Pending tags are held for user review in the Web UI.
"""

import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Optional

logger = logging.getLogger("filetagger.taxonomy")

TAGS_PATH    = Path.home() / ".filetagger" / "tags.json"
PENDING_PATH = Path.home() / ".filetagger" / "pending.json"


# ── Data helpers ─────────────────────────────────────────────────────────────

def _load(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text())
        except Exception:
            pass
    return {}


def _save(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))


# ── Approved taxonomy ────────────────────────────────────────────────────────

def load_taxonomy() -> dict:
    """
    Returns the approved tag library.

    Structure:
    {
      "finance": {
        "aliases": ["budget", "money", "invoice"],
        "category": "work",
        "added_at": "2026-04-16T..."
      },
      ...
    }
    """
    return _load(TAGS_PATH)


def save_taxonomy(taxonomy: dict):
    _save(TAGS_PATH, taxonomy)


def approved_tags() -> list[str]:
    """Return flat list of all approved tag names + their aliases."""
    tax = load_taxonomy()
    tags = set(tax.keys())
    for meta in tax.values():
        for alias in meta.get("aliases", []):
            tags.add(alias.lower())
    return sorted(tags)


def add_approved_tag(tag: str, category: str = "", aliases: list = None):
    """Add a tag to the approved library."""
    tag = tag.lower().strip()
    tax = load_taxonomy()
    tax[tag] = {
        "aliases": [a.lower() for a in (aliases or [])],
        "category": category,
        "added_at": datetime.now().isoformat(),
    }
    save_taxonomy(tax)
    logger.info(f"Approved tag added: {tag}")


def remove_approved_tag(tag: str):
    tax = load_taxonomy()
    tax.pop(tag.lower(), None)
    save_taxonomy(tax)


def add_alias(tag: str, alias: str):
    """Add an alias to an existing approved tag."""
    tax = load_taxonomy()
    tag = tag.lower()
    if tag in tax:
        aliases = tax[tag].get("aliases", [])
        if alias.lower() not in aliases:
            aliases.append(alias.lower())
        tax[tag]["aliases"] = aliases
        save_taxonomy(tax)


def normalize_tag(tag: str) -> Optional[str]:
    """
    If tag is an alias for an approved tag, return the canonical tag name.
    If tag is already approved, return it.
    Otherwise return None.
    """
    tag = tag.lower().strip()
    tax = load_taxonomy()
    if tag in tax:
        return tag
    for canonical, meta in tax.items():
        if tag in [a.lower() for a in meta.get("aliases", [])]:
            return canonical
    return None


# ── Pending queue ────────────────────────────────────────────────────────────

def load_pending() -> dict:
    """
    Returns pending tag proposals.

    Structure:
    {
      "opencode-ollama": {
        "proposed_at": "...",
        "file_count": 2,
        "example_files": ["file1.txt", "file2.txt"],
        "ai_context": "Used when tagging code files related to ollama"
      },
      ...
    }
    """
    return _load(PENDING_PATH)


def save_pending(pending: dict):
    _save(PENDING_PATH, pending)


def propose_tag(tag: str, filename: str, context: str = ""):
    """Record an AI-proposed tag for user review."""
    tag = tag.lower().strip()
    pending = load_pending()

    if tag not in pending:
        pending[tag] = {
            "proposed_at": datetime.now().isoformat(),
            "file_count": 0,
            "example_files": [],
            "ai_context": context,
        }

    pending[tag]["file_count"] += 1
    examples = pending[tag]["example_files"]
    if filename not in examples:
        examples.append(filename)
    pending[tag]["example_files"] = examples[:5]  # keep max 5 examples
    save_pending(pending)


def approve_pending_tag(tag: str, category: str = "") -> bool:
    """Move a tag from pending to approved."""
    pending = load_pending()
    if tag not in pending:
        return False
    add_approved_tag(tag, category=category)
    del pending[tag]
    save_pending(pending)
    logger.info(f"Pending tag approved: {tag}")
    return True


def reject_pending_tag(tag: str) -> bool:
    """Remove a tag from pending without approving."""
    pending = load_pending()
    if tag not in pending:
        return False
    del pending[tag]
    save_pending(pending)
    logger.info(f"Pending tag rejected: {tag}")
    return True


def merge_pending_tag(tag: str, into: str) -> bool:
    """
    Reject a pending tag and add it as an alias of an existing approved tag.
    """
    pending = load_pending()
    if tag not in pending:
        return False
    add_alias(into, tag)
    del pending[tag]
    save_pending(pending)
    logger.info(f"Pending tag '{tag}' merged into '{into}' as alias")
    return True


def pending_count() -> int:
    return len(load_pending())


# ── Tag resolution for the AI tagger ─────────────────────────────────────────

def resolve_tags(ai_tags: list[str], filename: str) -> tuple[list[str], list[str]]:
    """
    Given a list of AI-suggested tags, split into:
      - approved_tags: tags that exist in the taxonomy (or are aliases)
      - new_tags: tags not in taxonomy → go to pending queue

    Returns (approved, new)
    """
    approved = []
    new = []

    for tag in ai_tags:
        canonical = normalize_tag(tag)
        if canonical:
            if canonical not in approved:
                approved.append(canonical)
        else:
            new.append(tag)
            propose_tag(tag, filename)

    return approved, new


# ── Default taxonomy seed ─────────────────────────────────────────────────────

DEFAULT_TAXONOMY = {
    # Work & productivity
    "work":         {"aliases": ["professional", "job", "office"], "category": "work"},
    "finance":      {"aliases": ["budget", "money", "invoice", "billing", "tax", "expense"], "category": "work"},
    "legal":        {"aliases": ["contract", "agreement", "law"], "category": "work"},
    "report":       {"aliases": ["analysis", "summary", "review"], "category": "work"},
    "project":      {"aliases": ["plan", "roadmap", "milestone"], "category": "work"},
    "presentation": {"aliases": ["slides", "deck", "pptx"], "category": "work"},
    "spreadsheet":  {"aliases": ["excel", "xlsx", "data"], "category": "work"},
    "resume":       {"aliases": ["cv", "curriculum-vitae"], "category": "work"},
    "email":        {"aliases": ["correspondence", "letter", "memo"], "category": "work"},
    "meeting":      {"aliases": ["minutes", "agenda", "notes"], "category": "work"},

    # Education
    "education":    {"aliases": ["school", "university", "course", "class"], "category": "education"},
    "research":     {"aliases": ["paper", "study", "thesis", "dissertation"], "category": "education"},
    "notes":        {"aliases": ["lecture", "study-notes", "notebook"], "category": "education"},
    "assignment":   {"aliases": ["homework", "essay", "exam"], "category": "education"},

    # Technical
    "code":         {"aliases": ["programming", "software", "script", "dev"], "category": "technical"},
    "config":       {"aliases": ["configuration", "settings", "dotfile"], "category": "technical"},
    "documentation":{"aliases": ["docs", "readme", "manual", "guide"], "category": "technical"},
    "database":     {"aliases": ["sql", "db", "data"], "category": "technical"},
    "infrastructure":{"aliases": ["devops", "server", "cloud", "docker"], "category": "technical"},
    "security":     {"aliases": ["cybersecurity", "pentest", "vulnerability", "soc"], "category": "technical"},
    "ai":           {"aliases": ["machine-learning", "ml", "llm", "model"], "category": "technical"},

    # Personal
    "personal":     {"aliases": ["private", "home"], "category": "personal"},
    "medical":      {"aliases": ["health", "doctor", "prescription"], "category": "personal"},
    "travel":       {"aliases": ["vacation", "trip", "itinerary"], "category": "personal"},
    "photo":        {"aliases": ["image", "picture", "photography"], "category": "personal"},
    "video":        {"aliases": ["movie", "film", "recording"], "category": "personal"},
    "music":        {"aliases": ["audio", "song", "album"], "category": "personal"},
    "receipt":      {"aliases": ["purchase", "order", "transaction"], "category": "personal"},

    # Military / Government (given your background)
    "military":     {"aliases": ["army", "dod", "defense", "armed-forces"], "category": "military"},
    "government":   {"aliases": ["federal", "agency", "nasa", "official"], "category": "military"},
    "training":     {"aliases": ["exercise", "drill", "instruction"], "category": "military"},
    "operations":   {"aliases": ["ops", "mission", "deployment"], "category": "military"},
    "intelligence": {"aliases": ["intel", "assessment", "brief"], "category": "military"},

    # Archive / misc
    "archive":      {"aliases": ["old", "backup", "archived"], "category": "misc"},
    "template":     {"aliases": ["form", "blank", "boilerplate"], "category": "misc"},
    "reference":    {"aliases": ["resource", "reference-material"], "category": "misc"},
    "draft":        {"aliases": ["wip", "work-in-progress"], "category": "misc"},
}


def init_taxonomy():
    """Seed the taxonomy with defaults if it doesn't exist."""
    if not TAGS_PATH.exists():
        now = datetime.now().isoformat()
        seeded = {}
        for tag, meta in DEFAULT_TAXONOMY.items():
            seeded[tag] = {**meta, "added_at": now}
        save_taxonomy(seeded)
        logger.info(f"Taxonomy seeded with {len(seeded)} default tags")
        return True
    return False