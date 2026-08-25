#!/usr/bin/env bash
# The "Local" source — quotas for the providers authenticated on THIS Mac,
# queried from each provider's own usage API using the credentials already here.
# It never talks to a gateway, only to the providers, so it works with no gateway
# at all (the menu-bar app's "Local" option).
#
# Sources, all read locally and best-effort (a provider is shown only when its
# credential exists here):
#   • Claude  — ~/.claude/.credentials.json or the login Keychain
#               ("Claude Code-credentials") → api.anthropic.com/api/oauth/usage
#   • Codex   — the freshest of ~/.codex/auth.json or a Goose
#               chatgpt_codex/tokens.json → chatgpt.com/backend-api/wham/usage
#   • OpenRouter — OPENROUTER_API_KEY from the env or ~/.hermes/.env
#               → openrouter.ai/api/v1/credits
#
# Portable: system python3 + security(1) only (no Hermes venv / httpx). Prints
# the same QuotaPayload JSON the gateway plugin returns on stdout; on failure
# (no local provider credentials at all) prints a one-line reason to stderr and
# exits non-zero, so the app can show a "sign in" state.
set -euo pipefail
exec /usr/bin/env python3 - "$@" <<'PY'
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"


def fail(msg):
    sys.stderr.write(msg.rstrip() + "\n")
    sys.exit(1)


def _get(url, headers, timeout=15):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def _iso(value):
    return value if isinstance(value, str) and value else None


def _pct(value):
    if value is None:
        return None
    try:
        used = float(value)
    except (TypeError, ValueError):
        return None
    return max(0.0, min(100.0, used))


def _window(label, used, resets_at=None, remaining_amount=None, currency=None, detail=None):
    used = _pct(used)
    warning = (used is not None and used >= 85.0) or (
        remaining_amount is not None and remaining_amount <= 0.0
    )
    return {
        "label": label,
        "used_percent": used,
        "remaining_percent": None if used is None else 100.0 - used,
        "remaining_amount": remaining_amount,
        "currency": currency,
        "resets_at": _iso(resets_at),
        "detail": detail,
        "warning": warning,
    }


def _provider(provider, label, status, windows, source=None, plan=None, details=None, message=None):
    return {
        "provider": provider,
        "label": label,
        "status": status,
        "source": source,
        "plan": plan,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "windows": windows or [],
        "details": details or [],
        "message": message,
    }


# --- Claude (Anthropic OAuth usage) --------------------------------------------
def _anthropic_token():
    path = HOME / ".claude" / ".credentials.json"
    if path.exists():
        try:
            data = json.loads(path.read_text())
            token = ((data.get("claudeAiOauth") or {}).get("accessToken") or "").strip()
            if token:
                return token
        except Exception:
            pass
    try:
        raw = subprocess.check_output(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            stderr=subprocess.DEVNULL,
        ).decode()
        return ((json.loads(raw).get("claudeAiOauth") or {}).get("accessToken") or "").strip() or None
    except Exception:
        return None


def anthropic_provider():
    token = _anthropic_token()
    if not token:
        return None
    if not token.startswith("sk-ant-oat"):
        return _provider(
            "anthropic", "Claude", "unavailable", [],
            message="Claude account limits need an OAuth (Claude subscription) login.",
        )
    try:
        payload = _get(
            "https://api.anthropic.com/api/oauth/usage",
            {
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2.1.0",
            },
        )
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            return _provider("anthropic", "Claude", "unavailable", [],
                             message="Sign in to Claude (claude login) to see limits.")
        return _provider("anthropic", "Claude", "unavailable", [], message=f"Claude usage error (HTTP {exc.code}).")
    except Exception as exc:
        return _provider("anthropic", "Claude", "unavailable", [], message=f"Could not reach Claude usage: {exc}")
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
        windows.append(_window(wlabel, used, resets_at=window.get("resets_at")))
    details = []
    extra = payload.get("extra_usage") or {}
    if extra.get("is_enabled"):
        used_credits, monthly_limit = extra.get("used_credits"), extra.get("monthly_limit")
        currency = extra.get("currency") or "USD"
        if isinstance(used_credits, (int, float)) and isinstance(monthly_limit, (int, float)):
            details.append(f"Extra usage: {used_credits:.2f} / {monthly_limit:.2f} {currency}")
    return _provider("anthropic", "Claude", "ok", windows, source="oauth_usage_api", details=details)


# --- Codex (ChatGPT usage) -----------------------------------------------------
def _jwt_exp(token):
    try:
        part = token.split(".")[1]
        pad = "=" * (-len(part) % 4)
        return json.loads(base64.urlsafe_b64decode(part + pad)).get("exp")
    except Exception:
        return None


def _codex_creds():
    # Every candidate ChatGPT/Codex token store on this Mac; pick the one whose
    # access token is valid the longest so a stale Goose token never shadows a
    # fresh Codex CLI login (or vice-versa).
    candidates = []
    for path in (HOME / ".codex" / "auth.json", HOME / ".config/goose/chatgpt_codex/tokens.json"):
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text())
        except Exception:
            continue
        tokens = data.get("tokens") if isinstance(data.get("tokens"), dict) else data
        token = (tokens.get("access_token") or "").strip()
        if not token:
            continue
        candidates.append((_jwt_exp(token) or 0, token, (tokens.get("account_id") or "").strip() or None))
    if not candidates:
        return None
    candidates.sort(reverse=True)
    return candidates[0][1], candidates[0][2]


def codex_provider():
    creds = _codex_creds()
    if not creds:
        return None
    token, account_id = creds
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json", "User-Agent": "codex-cli"}
    if account_id:
        headers["ChatGPT-Account-Id"] = account_id
    try:
        payload = _get("https://chatgpt.com/backend-api/wham/usage", headers)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            return _provider("openai-codex", "Codex", "unavailable", [],
                             message="Codex token expired — re-run your Codex/ChatGPT sign-in.")
        return _provider("openai-codex", "Codex", "unavailable", [], message=f"Codex usage error (HTTP {exc.code}).")
    except Exception as exc:
        return _provider("openai-codex", "Codex", "unavailable", [], message=f"Could not reach Codex usage: {exc}")
    rate_limit = payload.get("rate_limit") or {}
    windows = []
    for key in ("primary_window", "secondary_window"):
        window = rate_limit.get(key) or {}
        used = window.get("used_percent")
        if used is None:
            continue
        reset_at = window.get("reset_at")
        wlabel = "Session" if key == "primary_window" else "Weekly"
        # The API conveys the window length only via reset distance; a reset more
        # than ~2 days out is the weekly allowance, otherwise the ~5h session.
        parsed = None
        if isinstance(reset_at, str) and reset_at:
            try:
                parsed = datetime.fromisoformat(reset_at.replace("Z", "+00:00"))
            except Exception:
                parsed = None
        if parsed is not None:
            now = datetime.now(parsed.tzinfo or timezone.utc)
            wlabel = "Weekly" if (parsed - now).total_seconds() > 2 * 86400 else "Session"
        windows.append(_window(wlabel, used, resets_at=reset_at if isinstance(reset_at, str) else None))
    details = []
    reset_credits = payload.get("rate_limit_reset_credits") or {}
    banked = reset_credits.get("available_count")
    if isinstance(banked, (int, float)) and int(banked) > 0:
        count = int(banked)
        details.append(f"You have {count} reset{'s' if count != 1 else ''} banked - use /usage reset to activate")
    credits = payload.get("credits") or {}
    if credits.get("has_credits"):
        balance = credits.get("balance")
        if isinstance(balance, (int, float)):
            details.append(f"Credits balance: ${float(balance):.2f}")
        elif credits.get("unlimited"):
            details.append("Credits balance: unlimited")
    plan = payload.get("plan_type")
    plan = str(plan).replace("_", " ").title() if plan else None
    return _provider("openai-codex", "Codex", "ok", windows, source="usage_api", plan=plan, details=details)


# --- OpenRouter (credits API) --------------------------------------------------
def _openrouter_key():
    key = (os.environ.get("OPENROUTER_API_KEY") or "").strip()
    if key:
        return key
    env_path = HOME / ".hermes" / ".env"
    if env_path.exists():
        try:
            for line in env_path.read_text().splitlines():
                line = line.strip()
                if line.startswith("OPENROUTER_API_KEY=") and not line.startswith("#"):
                    value = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if value and value != "CHANGEME":
                        return value
        except Exception:
            pass
    return None


def openrouter_provider():
    key = _openrouter_key()
    if not key:
        return None
    headers = {"Authorization": f"Bearer {key}", "Accept": "application/json", "User-Agent": UA}
    try:
        credits = (_get("https://openrouter.ai/api/v1/credits", headers, timeout=10).get("data") or {})
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            return _provider("openrouter", "OpenRouter", "unavailable", [], message="OpenRouter key rejected — check OPENROUTER_API_KEY.")
        return _provider("openrouter", "OpenRouter", "unavailable", [], message=f"OpenRouter error (HTTP {exc.code}).")
    except Exception as exc:
        return _provider("openrouter", "OpenRouter", "unavailable", [], message=f"Could not reach OpenRouter: {exc}")
    total = float(credits.get("total_credits") or 0.0)
    usage = float(credits.get("total_usage") or 0.0)
    remaining = max(0.0, total - usage)
    window = _window("Account credits", None, remaining_amount=remaining, currency="USD",
                     detail=f"${remaining:.2f} of ${total:.2f} left" if total > 0 else f"${remaining:.2f} available")
    return _provider("openrouter", "OpenRouter", "ok", [window], source="credits_api")


providers = [p for p in (anthropic_provider(), codex_provider(), openrouter_provider()) if p is not None]
if not providers:
    fail("Sign in to Claude, Codex, or OpenRouter to see quotas.")

print(json.dumps({
    "broker": os.uname().nodename,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "source": "local",
    "providers": providers,
}))
PY
