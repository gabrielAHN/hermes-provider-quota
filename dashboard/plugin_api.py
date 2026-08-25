from __future__ import annotations

import json
import os
import re
import socket
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Annotated, Any

from fastapi import APIRouter, Query, Response

from agent.account_usage import fetch_account_usage

router = APIRouter()

# Nice labels for the providers Hermes ships account-usage support for. Any other
# slug still works — it just gets a title-cased label.
_KNOWN_LABELS = {
    "openrouter": "OpenRouter",
    "anthropic": "Claude",
    "openai-codex": "Codex",
}
_DEFAULT_PROVIDERS = "openrouter,anthropic,openai-codex"


def _label_for(slug: str) -> str:
    return _KNOWN_LABELS.get(slug, slug.replace("-", " ").replace("_", " ").title())


def _configured_providers() -> tuple[tuple[str, str], ...]:
    """Which providers this gateway's dashboard reports on.

    Configurable per gateway via the ``PROVIDER_QUOTA_PROVIDERS`` env var
    (comma-separated ``slug`` or ``slug=Label`` items), so anyone can reuse this
    plugin with their own gateway's provider set instead of a hardcoded list.
    Defaults to the providers Hermes ships usage support for. Whatever the set,
    every quota is read through this gateway's own ``account_usage`` credentials,
    so the plugin stays linked to the gateway it's installed in.
    """
    raw = os.environ.get("PROVIDER_QUOTA_PROVIDERS", "").strip() or _DEFAULT_PROVIDERS
    providers: list[tuple[str, str]] = []
    seen: set[str] = set()
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        slug, sep, label = item.partition("=")
        slug = slug.strip()
        if not slug or slug in seen:
            continue
        seen.add(slug)
        providers.append((slug, label.strip() if sep and label.strip() else _label_for(slug)))
    return tuple(providers)


CACHE_SECONDS = 60
_cache: dict[str, Any] | None = None
_cache_at = 0.0
_lock = Lock()


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(timezone.utc).isoformat()


def _file_anthropic_token() -> str | None:
    """Resolve the gateway's `claude login` OAuth token from the credentials FILE
    (refreshing if needed). On macOS, Hermes' account_usage reads the login
    Keychain first, whose Claude session can be expired even though the file token
    (kept fresh by the ACP bridge) is valid — that's why Claude can read as
    "authentication required" on the gateway despite a working `claude` login.
    Reading the file directly sidesteps that, and stays linked to the gateway's
    own subscription."""
    try:
        from agent.anthropic_adapter import (
            _read_claude_code_credentials_from_file,
            _refresh_oauth_token,
            is_claude_code_token_valid,
        )
        creds = _read_claude_code_credentials_from_file()
        if not creds:
            return None
        if is_claude_code_token_valid(creds):
            return (creds.get("accessToken") or "").strip() or None
        return (_refresh_oauth_token(creds) or "").strip() or None
    except Exception:
        return None


def _anthropic_direct(label: str) -> dict[str, Any] | None:
    """Query the Anthropic OAuth usage API with the gateway's file token, used as
    a fallback when account_usage can't (stale login-Keychain session). Mirrors
    account_usage's anthropic window mapping."""
    token = _file_anthropic_token()
    if not token or not token.startswith("sk-ant-oat"):
        return None
    try:
        req = urllib.request.Request(
            "https://api.anthropic.com/api/oauth/usage",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2.1.0",
            },
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            payload = json.load(resp) or {}
    except Exception:
        return None
    windows = []
    for key, wlabel in (
        ("five_hour", "Current session"),
        ("seven_day", "Current week"),
        ("seven_day_opus", "Opus week"),
        ("seven_day_sonnet", "Sonnet week"),
    ):
        window = payload.get(key) or {}
        util = window.get("utilization")
        if util is None:
            continue
        used = float(util) * 100 if float(util) <= 1 else float(util)
        used = max(0.0, min(100.0, used))
        windows.append({
            "label": wlabel,
            "used_percent": used,
            "remaining_percent": 100.0 - used,
            "remaining_amount": None,
            "currency": None,
            "resets_at": window.get("resets_at"),
            "detail": None,
            "warning": used >= 85.0,
        })
    if not windows:
        return None
    return {
        "provider": "anthropic",
        "label": label,
        "status": "ok",
        "source": "oauth_usage_api (file token)",
        "plan": None,
        "fetched_at": _iso(datetime.now(timezone.utc)),
        "windows": windows,
        "details": [],
        "message": None,
    }


def _provider(provider: str, label: str) -> dict[str, Any]:
    result = _provider_via_account_usage(provider, label)
    # Claude on a gateway whose login-Keychain session is stale reads as
    # authentication_required even though the `claude login` file token works —
    # fall back to querying usage with that file token so it still shows.
    if provider == "anthropic" and result.get("status") != "ok":
        fallback = _anthropic_direct(label)
        if fallback is not None:
            return fallback
    return result


def _provider_via_account_usage(provider: str, label: str) -> dict[str, Any]:
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
            "message": f"Sign in to {label} on the gateway.",
        }
    windows = []
    for window in snapshot.windows:
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
    details = list(snapshot.details)
    if provider == "openrouter":
        # Surface the OpenRouter credit balance instead of a bare "ok". account_usage
        # only reports it as a "Credits balance: $N" detail string (from the gateway's
        # own credentials — respecting the gateway's access), so lift the number into
        # an "Account credits" window the renderer can show, and drop the now-duplicate
        # detail line while keeping the rest (e.g. "API key usage: …").
        balance = None
        for line in details:
            match = re.search(r"Credits balance:\s*\$([0-9]+(?:\.[0-9]+)?)", line)
            if match:
                balance = float(match.group(1))
                break
        if balance is not None:
            details = [d for d in details if not d.startswith("Credits balance:")]
            windows.insert(0, {
                "label": "Account credits",
                "used_percent": None,
                "remaining_percent": None,
                "remaining_amount": balance,
                "currency": "USD",
                "resets_at": None,
                "detail": f"${balance:.2f} available",
                "warning": balance <= 0.0,
            })
    status = "ok" if snapshot.available else "unavailable"
    return {
        "provider": provider,
        "label": label,
        "status": status,
        "source": snapshot.source,
        "plan": snapshot.plan,
        "fetched_at": _iso(snapshot.fetched_at),
        "windows": windows,
        "details": details,
        "message": snapshot.unavailable_reason,
    }


def _load(refresh: bool) -> dict[str, Any]:
    global _cache, _cache_at
    now = time.monotonic()
    with _lock:
        if not refresh and _cache is not None and now - _cache_at < CACHE_SECONDS:
            return _cache
        configured = _configured_providers()
        providers = [_provider(slug, label) for slug, label in configured]
        _cache = {
            # broker identifies the gateway host these quotas belong to, so a
            # client can tell which gateway it's linked to.
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
