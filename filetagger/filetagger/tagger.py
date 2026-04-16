"""AI tagging via Ollama API."""
import json
import logging
import httpx
from pathlib import Path

logger = logging.getLogger("filetagger.tagger")

SYSTEM_PROMPT = """You are a file tagging assistant. Given file content and metadata, you generate:
1. A concise one-sentence summary (max 20 words)
2. A list of 3-8 relevant tags (lowercase, single words or short hyphenated phrases)

Tags should describe: topic, type, project, subject matter, time period, people, organizations, or any relevant context.

Respond ONLY with valid JSON in this exact format, no other text:
{"summary": "...", "tags": ["tag1", "tag2", "tag3"]}"""


def build_prompt(filename: str, category: str, extension: str,
                 content: str, size_bytes: int) -> str:
    size_kb = size_bytes // 1024 if size_bytes else 0
    content_section = f"\n\nFILE CONTENT (first {len(content)} chars):\n{content}" if content else ""
    return f"""FILE: {filename}
TYPE: {category} ({extension})
SIZE: {size_kb} KB{content_section}

Generate summary and tags for this file."""


def tag_file(filename: str, category: str, extension: str,
             content: str, size_bytes: int, config: dict) -> tuple[str, list]:
    """Returns (summary, tags). Raises on failure."""
    base_url = config["ollama_base_url"].rstrip("/")
    model = config["ollama_model"]
    prompt = build_prompt(filename, category, extension, content, size_bytes)

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt}
        ],
        "stream": False,
        "options": {
            "temperature": 0.2,
            "num_predict": 256
        }
    }

    try:
        with httpx.Client(timeout=60.0) as client:
            resp = client.post(f"{base_url}/api/chat", json=payload)
            resp.raise_for_status()
            data = resp.json()

        raw = data["message"]["content"].strip()

        # Strip markdown code fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
            raw = raw.strip()

        parsed = json.loads(raw)
        summary = parsed.get("summary", "")
        tags = parsed.get("tags", [])

        # Sanitize tags
        tags = [str(t).lower().strip().replace(" ", "-")[:40] for t in tags if t]
        tags = list(dict.fromkeys(tags))[:10]  # dedupe, max 10

        return summary, tags

    except httpx.HTTPStatusError as e:
        raise RuntimeError(f"Ollama HTTP error {e.response.status_code}: {e.response.text[:200]}")
    except httpx.ConnectError:
        raise RuntimeError(f"Cannot connect to Ollama at {base_url}")
    except json.JSONDecodeError as e:
        logger.warning(f"JSON parse failed for {filename}, raw: {raw[:200]}")
        # Return filename-based fallback
        stem = Path(filename).stem.replace("_", "-").replace(" ", "-").lower()
        return f"File: {filename}", [category, stem[:40]]
    except Exception as e:
        raise RuntimeError(f"Tagging failed: {e}")


def check_ollama(config: dict) -> tuple[bool, str]:
    """Check if Ollama is reachable and model is available."""
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
