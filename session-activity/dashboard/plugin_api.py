from __future__ import annotations

import json
import re
import socket
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import APIRouter

router = APIRouter()

# --- Live Hermes session/activity broker ---
# Reports the turns RUNNING right now so a client (the Provider Quotas menu-bar
# pet) can light a per-provider session indicator — including work the gateway
# REST never marks is_active, notably tui_gateway turns. This plugin runs ON the
# gateway host, so it reads the gateway LOGS (gui.log turn lifecycle + agent.log
# model/provider) and the active-sessions REGISTRY (desktop-surface leases). It
# NEVER touches the session DB or web_server internals — that is what got a
# previous plugin auto-disabled — so it stays enabled. Each live turn is returned
# with its model so the client colours it by provider (a "vendor/model" slug is
# OpenRouter, claude-* is Claude, gpt-*/codex is Codex).
_ACTIVITY_MAX_AGE = 900.0            # ignore log events older than this (s)
_RE_LOG_TS = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")
_RE_TUI_START = re.compile(r"tui prompt accepted:.*agent_session_id=(\S+)")
_RE_TUI_END = re.compile(r"tui turn (?:finished|failed|cancell?ed|aborted|error):.*agent_session_id=(\S+)")
_RE_MODEL = re.compile(r"\[(\d{8}_\d{6}_[0-9a-fA-F]+)\].*?model=(\S+)\s+provider=(\S+)")


def _hermes_home() -> Path:
    for mod in ("agent.paths", "hermes_cli.paths", "agent.config"):
        try:
            m = __import__(mod, fromlist=["get_hermes_home"])
            return Path(m.get_hermes_home())
        except Exception:
            continue
    return Path.home() / ".hermes"


def _tail_text(path: Path, max_bytes: int = 262144) -> str:
    try:
        size = path.stat().st_size
        with path.open("rb") as fh:
            if size > max_bytes:
                fh.seek(size - max_bytes)
            return fh.read().decode("utf-8", "replace")
    except Exception:
        return ""


def _log_ts(line: str) -> float | None:
    m = _RE_LOG_TS.match(line)
    if not m:
        return None
    try:
        # naive local time on THIS host; time.time() below is the same clock, so
        # the freshness delta is self-consistent regardless of the host's TZ.
        return datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").timestamp()
    except Exception:
        return None


def _active_tui_sessions(home: Path, now: float) -> dict[str, dict[str, Any]]:
    state: dict[str, tuple[float, str]] = {}
    for line in _tail_text(home / "logs" / "gui.log").splitlines():
        ts = _log_ts(line)
        if ts is None or now - ts > _ACTIVITY_MAX_AGE:
            continue
        m = _RE_TUI_START.search(line)
        if m:
            state[m.group(1)] = (ts, "start")
            continue
        m = _RE_TUI_END.search(line)
        if m:
            state[m.group(1)] = (ts, "end")
    return {
        sid: {"started_at": ts, "surface": "tui"}
        for sid, (ts, kind) in state.items()
        if kind == "start"
    }


def _registry_sessions(home: Path) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    regs = [home / "runtime" / "active_sessions.json"]
    try:
        regs += list((home / "profiles").glob("*/runtime/active_sessions.json"))
    except Exception:
        pass
    for reg in regs:
        try:
            data = json.loads(reg.read_text(encoding="utf-8"))
        except Exception:
            continue
        for e in (data.get("entries") if isinstance(data, dict) else data) or []:
            meta = e.get("metadata") if isinstance(e.get("metadata"), dict) else {}
            # `session_id` here is the AGENT session id (what agent.log tags model
            # lines with); `metadata.live_session_id` is the UI session — use the
            # agent id so the model lookup resolves.
            sid = str(e.get("session_id") or meta.get("live_session_id") or "").strip()
            if sid:
                out[sid] = {"started_at": e.get("started_at"), "surface": e.get("surface") or "desktop"}
    return out


def _models_for(home: Path, sids: set[str]) -> dict[str, tuple[str, str]]:
    if not sids:
        return {}
    out: dict[str, tuple[str, str]] = {}
    for line in _tail_text(home / "logs" / "agent.log").splitlines():
        m = _RE_MODEL.search(line)
        if m and m.group(1) in sids:
            out[m.group(1)] = (m.group(2), m.group(3))  # keep the latest
    return out


@router.get("/activity")
def activity() -> dict[str, Any]:
    now = time.time()
    home = _hermes_home()
    sessions: dict[str, dict[str, Any]] = {}
    try:
        sessions.update(_active_tui_sessions(home, now))
    except Exception:
        pass
    try:
        sessions.update(_registry_sessions(home))  # desktop leases (also live)
    except Exception:
        pass
    models = _models_for(home, set(sessions))
    out = []
    for sid, info in sessions.items():
        model, provider = models.get(sid, ("", ""))
        out.append({
            "session_id": sid,
            "surface": info.get("surface"),
            "started_at": info.get("started_at"),
            "model": model,
            "provider": provider,
            "is_active": True,
        })
    return {"broker": socket.gethostname(), "sessions": out}
