"""AI tagging via Ollama API."""
import json
import logging
import httpx
from pathlib import Path

logger = logging.getLogger("filetagger.tagger")


def _build_system_prompt(approved_tags: list[str]) -> str:
    if approved_tags:
        tag_list = "\n".join(f"  - {t}" for t in approved_tags[:150])
        tag_section = f"""
APPROVED TAG LIBRARY (use these whenever possible):
{tag_list}

TAG SELECTION RULES — FOLLOW STRICTLY:
1. ALWAYS prefer tags from the approved library above.
2. Only invent a NEW tag if NO approved tag adequately describes the file.
3. If you must invent a new tag, limit it to 1 new tag maximum per file.
4. New tags must be BROAD and REUSABLE (e.g. "geology" not "utah-rock-formations-2019").
5. Never create tags specific to a single file (filenames, project codes, dates).
6. Favor FEWER, MORE GENERAL tags over MANY SPECIFIC ones. 3-5 tags is ideal.
"""
    else:
        tag_section = """
TAG SELECTION RULES:
1. Generate 3-6 broad, reusable tags describing the file's topic and type.
2. Tags must be general enough to apply to multiple files.
3. Never use filenames, dates, or unique identifiers as tags.
"""

    return f"""You are a file tagging assistant. Given file content and metadata, generate:
1. A concise one-sentence summary (max 20 words)
2. A list of 3-6 relevant tags

{tag_section}

Respond ONLY with valid JSON in this exact format, no other text:
{{"summary": "...", "tags": ["tag1", "tag2", "tag3"]}}"""


def build_prompt(filename: str, category: str, extension: str,
                 content: str, size_bytes: int) -> str:
    size_kb = size_bytes // 1024 if size_bytes else 0
    content_section = f"\n\nFILE CONTENT (first {len(content)} chars):\n{content}" if content else ""
    return f"""FILE: {filename}
TYPE: {category} ({extension})
SIZE: {size_kb} KB{content_section}

Generate summary and tags for this file."""


def tag_file(filename: str, category: str, extension: str,
             content: str, size_bytes: int, config: dict,
             approved_tags: list[str] = None) -> tuple[str, list]:
    """Returns (summary, raw_ai_tags). Raises on failure."""
    base_url = config["ollama_base_url"].rstrip("/")
    model = config["ollama_model"]
    prompt = build_prompt(filename, category, extension, content, size_bytes)
    system = _build_system_prompt(approved_tags or [])

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user",   "content": prompt}
        ],
        "stream": False,
        "options": {"temperature": 0.2, "num_predict": 256}
    }

    try:
        with httpx.Client(timeout=60.0) as client:
            resp = client.post(f"{base_url}/api/chat", json=payload)
            resp.raise_for_status()
            data = resp.json()

        raw = data["message"]["content"].strip()
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
            raw = raw.strip()

        parsed = json.loads(raw)
        summary = parsed.get("summary", "")
        tags = parsed.get("tags", [])
        tags = [str(t).lower().strip().replace(" ", "-")[:40] for t in tags if t]
        tags = list(dict.fromkeys(tags))[:10]
        return summary, tags

    except httpx.HTTPStatusError as e:
        raise RuntimeError(f"Ollama HTTP error {e.response.status_code}: {e.response.text[:200]}")
    except httpx.ConnectError:
        raise RuntimeError(f"Cannot connect to Ollama at {base_url}")
    except json.JSONDecodeError:
        logger.warning(f"JSON parse failed for {filename}, raw: {raw[:200]}")
        stem = Path(filename).stem.replace("_", "-").replace(" ", "-").lower()
        return f"File: {filename}", [category, stem[:40]]
    except Exception as e:
        raise RuntimeError(f"Tagging failed: {e}")


def check_ollama(config: dict) -> tuple[bool, str]:
    base_url = config["ollama_base_url"].rstrip("/")
    model = config["ollama_model"]
    try:
        with httpx.Client(timeout=10.0) as client:
            resp = client.get(f"{base_url}/api/tags")
            resp.raise_for_status()
            data = resp.json()
            models = [m["name"].split(":")[0] for m in data.get("models", [])]
            model_base = model.split(":")[0]
            if model_base not in models:
                return False, f"Model '{model}' not found. Available: {', '.join(models) or 'none'}"
            return True, f"Connected to {base_url}, model '{model}' available"
    except httpx.ConnectError:
        return False, f"Cannot connect to Ollama at {base_url}"
    except Exception as e:
        return False, f"Ollama check failed: {e}"