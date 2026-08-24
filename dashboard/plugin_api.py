from __future__ import annotations

import json
import socket
import time
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Annotated, Any

from fastapi import APIRouter, Query, Response

from agent.account_usage import fetch_account_usage

router = APIRouter()

PROVIDERS = (
    ("openrouter", "OpenRouter"),
    ("anthropic", "Claude"),
    ("openai-codex", "Codex"),
)
CACHE_SECONDS = 60
_cache: dict[str, Any] | None = None
_cache_at = 0.0
_lock = Lock()


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(timezone.utc).isoformat()


def _provider(provider: str, label: str) -> dict[str, Any]:
    snapshot = fetch_account_usage(provider)
    if snapshot is None:
        return {
            "provider": provider,
            "label": label,
            "status": "authentication_required",
            "source": None,
            "plan": None,
            "fetched_at": None,
            "windows": [],
            "details": [],
            "message": f"Sign in to {label} on the Mac mini Hermes gateway.",
        }
    windows = []
    for window in snapshot.windows:
        if provider == "openrouter" and window.label != "Account credits":
            continue
        used = None if window.used_percent is None else max(0.0, min(100.0, float(window.used_percent)))
        remaining_amount = getattr(window, "remaining_amount", None)
        remaining_amount = None if remaining_amount is None else max(0.0, float(remaining_amount))
        window_label = window.label
        if provider == "openai-codex" and window.reset_at is not None:
            # The Codex/ChatGPT usage API only conveys the window length via
            # limit_window_seconds, which account_usage drops before we see it —
            # and on Plus the single returned window is the 7-day allowance yet
            # core hardcodes its label to "Session". Re-derive from the reset
            # distance: a reset >2 days out is the weekly quota, otherwise it's
            # the ~5h session window.
            now = datetime.now(window.reset_at.tzinfo or timezone.utc)
            seconds_to_reset = (window.reset_at - now).total_seconds()
            window_label = "Weekly" if seconds_to_reset > 2 * 86400 else "Session"
        windows.append(
            {
                "label": window_label,
                "used_percent": used,
                "remaining_percent": None if used is None else 100.0 - used,
                "remaining_amount": remaining_amount,
                "currency": getattr(window, "currency", None),
                "resets_at": _iso(window.reset_at),
                "detail": window.detail,
                "warning": (used is not None and used >= 85.0)
                or (remaining_amount is not None and remaining_amount <= 0.0),
            }
        )
    status = "ok" if snapshot.available else "unavailable"
    return {
        "provider": provider,
        "label": label,
        "status": status,
        "source": snapshot.source,
        "plan": snapshot.plan,
        "fetched_at": _iso(snapshot.fetched_at),
        "windows": windows,
        "details": [] if provider == "openrouter" else list(snapshot.details),
        "message": snapshot.unavailable_reason,
    }


def _load(refresh: bool) -> dict[str, Any]:
    global _cache, _cache_at
    now = time.monotonic()
    with _lock:
        if not refresh and _cache is not None and now - _cache_at < CACHE_SECONDS:
            return _cache
        providers = [_provider(provider, label) for provider, label in PROVIDERS]
        _cache = {
            "broker": socket.gethostname(),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "cache_seconds": CACHE_SECONDS,
            "providers": providers,
        }
        _cache_at = time.monotonic()
        return _cache


@router.get("/quotas")
def quotas(refresh: Annotated[bool, Query()] = False) -> dict[str, Any]:
    return _load(refresh)


# --- Pets: expose the pets installed ON THIS GATEWAY so a remote client (e.g.
# the menu-bar app) can list and fetch pets that were downloaded here, since a
# remote Hermes Desktop downloads pets to the gateway, not the client. ---
def _pets_dirs() -> list[Path]:
    # Mirror ONLY the profile the gateway serves (get_hermes_home()/pets — the
    # dashboard's profile), which is exactly the pets the remote Hermes Desktop's
    # pet.install / pet.remove RPCs operate on. Scanning other profiles would
    # surface pets the Desktop can't manage, so a delete there would never
    # reflect in the menu (that was the "deleted pet still showing" bug).
    try:
        from agent.pet.store import pets_dir
        return [pets_dir()]
    except Exception:
        return [Path.home() / ".hermes" / "pets"]


def _installed_pets() -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for base in _pets_dirs():
        try:
            children = sorted(base.iterdir())
        except Exception:
            continue
        for directory in children:
            if not directory.is_dir() or directory.name.startswith("."):
                continue
            meta_path = directory / "pet.json"
            if not meta_path.exists():
                continue
            try:
                meta = json.loads(meta_path.read_text())
            except Exception:
                continue
            pet_id = meta.get("id", directory.name)
            if pet_id in seen:
                continue
            sheet = directory / (meta.get("spritesheetPath") or "spritesheet.webp")
            if not sheet.exists():
                continue
            seen.add(pet_id)
            out.append({
                "id": pet_id,
                "displayName": meta.get("displayName", directory.name),
                "spritesheetPath": sheet.name,
                "path": sheet,
            })
    return out


@router.get("/pets")
def pets() -> dict[str, Any]:
    return {"pets": [{"id": p["id"], "displayName": p["displayName"],
                      "spritesheetPath": p["spritesheetPath"]} for p in _installed_pets()]}


@router.get("/pets/{pet_id}/spritesheet")
def pet_spritesheet(pet_id: str) -> Response:
    for pet in _installed_pets():
        if pet["id"] == pet_id:
            path: Path = pet["path"]
            media = "image/webp" if path.suffix.lower() == ".webp" else "image/png"
            return Response(content=path.read_bytes(), media_type=media)
    return Response(status_code=404)
