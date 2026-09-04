#!/usr/bin/env bash
# Provider quotas for the menu-bar, through the Hermes Desktop app's own gateway
# session. Works with whatever gateway the Desktop is bound to — a LOCAL backend
# or any REMOTE gateway (OAuth/Authelia) — exactly like Hermes Desktop's own
# Provider Quotas page (/api/plugins/provider-quota/quotas).
#
# Portable: uses only the system python3 + openssl + security (no Hermes venv,
# httpx, or cryptography), so it runs on a client Mac that has Hermes Desktop but
# no local gateway install. Prints the QuotaPayload JSON to stdout on success;
# on any failure prints a one-line reason to stderr and exits non-zero.
set -euo pipefail
exec /usr/bin/env python3 - "$@" <<'PY'
import base64, hashlib, json, subprocess, sys, urllib.request, urllib.error
from pathlib import Path

SUPPORT = Path.home() / "Library/Application Support/Hermes"
# Optional args: $1 = gateway endpoint path (default: the quotas endpoint),
# $2 = output file for binary bodies (e.g. a pet spritesheet); otherwise the
# body is written to stdout.
ENDPOINT = sys.argv[1] if len(sys.argv) > 1 else "/api/plugins/provider-quota/quotas?refresh=true"
OUT = sys.argv[2] if len(sys.argv) > 2 else None
# Activity polls run on the menu-bar's 1s timer and only read session lists, so a
# slow gateway call must fail FAST — a 20s hang would stall the in-flight guard
# and make a session's dot appear (or clear) many seconds late. Quota fetches hit
# slow provider APIs, so they keep the generous timeout.
TIMEOUT = 6 if ENDPOINT == "--activity" else 20


def fail(msg):
    sys.stderr.write(msg.rstrip() + "\n")
    sys.exit(1)


def emit(data):
    if OUT:
        with open(OUT, "wb") as fh:
            fh.write(data)
    else:
        sys.stdout.buffer.write(data)


def read_json(name):
    try:
        return json.loads((SUPPORT / name).read_text())
    except Exception:
        return None


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # surface 3xx as an error instead of following to a login page


_opener = urllib.request.build_opener(_NoRedirect)

# Gateways are often fronted by Cloudflare, which 403s the default
# "Python-urllib/x.y" agent. Send a browser-like UA so the request is allowed.
_USER_AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
               "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")


def http_get(url, headers):
    hdrs = dict(headers)
    hdrs.setdefault("User-Agent", _USER_AGENT)
    req = urllib.request.Request(url, headers=hdrs)
    try:
        with _opener.open(req, timeout=TIMEOUT) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, b""
    except Exception as exc:
        fail("Cannot reach Hermes gateway: %s" % exc)


# --- Which gateway is the Desktop bound to? Prefer the primary entry in the v2
# connections.json, fall back to the legacy connection.json. ---
conns = read_json("connections.json") or {}
primary = None
if isinstance(conns.get("connections"), list) and conns["connections"]:
    by_id = {c.get("id"): c for c in conns["connections"]}
    primary = by_id.get(conns.get("primary")) or conns["connections"][0]

if primary is not None:
    kind = primary.get("kind")
    url = (primary.get("url") or "").rstrip("/")
else:
    legacy = read_json("connection.json") or {}
    kind = legacy.get("mode")
    url = ""
    if kind and kind != "local":
        url = ((legacy.get(kind) or legacy.get("remote") or {}).get("url") or "").rstrip("/")

if not kind:
    fail("Hermes Desktop is not set up.")

def _norm(value):
    return value.strip().strip("/")


# --- Build a `fetch(path) -> (status, body)` bound to the gateway the Desktop is
# bound to: a loopback bind (local mode) needs no auth; a remote gateway uses the
# Desktop's OAuth session. Resolving this once lets one process serve several
# endpoints (see --activity) with a single Keychain read / token decrypt. ---
if kind == "local":
    own = read_json("backend-ownership.json") or {}
    local_url = None
    for backend in own.get("backends") or []:
        candidate = (backend.get("url") or backend.get("baseUrl") or "").rstrip("/")
        if candidate:
            local_url = candidate
            break
        port = backend.get("port")
        if port:
            local_url = "http://127.0.0.1:%s" % port
            break
    if not local_url:
        fail("Hermes Desktop is in local mode but no local gateway is running.")

    def fetch(path):
        return http_get(local_url + path, {"Accept": "*/*"})

    EXPIRED_MSG = "Local Hermes gateway returned HTTP %s."
else:
    if not url:
        fail("Hermes Desktop has no gateway configured.")
    tokens = read_json("native-oauth-tokens.json")
    if tokens is None:
        fail("Sign in to Hermes Desktop.")
    entry = tokens.get(url) or next((v for k, v in tokens.items() if _norm(k) == _norm(url)), None)
    if not entry:
        fail("Sign in to Hermes Desktop (%s)." % url)

    value = entry.get("value") or ""
    if entry.get("encoding") == "safeStorage":
        # Electron safeStorage v10: AES-128-CBC, key = PBKDF2-HMAC-SHA1(secret,
        # "saltysalt", 1003, 16), IV = 16 spaces. Decrypt with openssl to avoid a
        # python crypto dependency.
        try:
            secret = subprocess.check_output(
                ["security", "find-generic-password", "-s", "Hermes Safe Storage", "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
        except Exception as exc:
            fail("Cannot read 'Hermes Safe Storage' Keychain key: %s" % exc)
        key = hashlib.pbkdf2_hmac("sha1", secret.encode(), b"saltysalt", 1003, dklen=16)
        raw = base64.b64decode(value)
        if raw[:3] != b"v10":
            fail("Unexpected Hermes Desktop token format.")
        proc = subprocess.run(
            ["openssl", "enc", "-d", "-aes-128-cbc", "-K", key.hex(),
             "-iv", "20" * 16, "-nopad"],
            input=raw[3:], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        plaintext = proc.stdout
        if not plaintext:
            fail("Cannot decrypt Hermes Desktop session token (openssl).")
        plaintext = plaintext[: -plaintext[-1]]  # strip PKCS7 padding
        session = json.loads(plaintext.decode())
    else:
        session = json.loads(value)

    access_token = session.get("accessToken") or ""
    if not access_token:
        fail("Sign in to Hermes Desktop.")

    def fetch(path):
        return http_get(url + path, {"Authorization": "Bearer " + access_token, "Accept": "*/*"})

    EXPIRED_MSG = "Hermes gateway returned HTTP %s."


def get_json(path):
    status, body = fetch(path)
    if status != 200:
        return None
    try:
        return json.loads(body)
    except Exception:
        return None


# --- Activity mode: resolve the gateway ONCE, then fetch /api/status plus each
# profile's recent sessions in the same process, and emit a compact summary the
# menu-bar uses to light the Hermes pet. Bot turns run as `source: cli` sessions
# that DON'T show up in the aggregate active_agents/active_sessions counters, so
# we return the per-session flags (is_active / ended_at / last_active) and let the
# app decide what's "running". Never fails: a signed-out gateway just yields an
# empty summary so the pet quietly stays idle. ---
if ENDPOINT == "--activity":
    import re, time
    from concurrent.futures import ThreadPoolExecutor

    def _dot_provider(s):
        # Colour the pet's dot by the MODEL FAMILY the user reasons about — Claude
        # vs Codex vs OpenRouter — resolved from `model`, which is populated from
        # the moment a session starts. We do NOT lead with `billing_provider`: it's
        # only stamped by usage accounting AFTER the first response (null on early
        # and failed turns → grey), and for a Claude model served through Copilot it
        # reads "copilot-acp" → wrong colour. OpenRouter serves "vendor/model" slugs
        # (qwen/…, deepseek/…, anthropic/…, openai/…), so ANY "/" means OpenRouter.
        # Fall back to billing_provider / provider only when the family is unknown.
        model = (s.get("model") or "").lower()
        if model:
            if "/" in model:
                return "openrouter"
            if model.startswith("claude"):
                return "anthropic"
            if model.startswith("gpt") or "codex" in model or model.startswith(("o1", "o3", "o4")):
                return "openai-codex"
        return s.get("billing_provider") or s.get("provider") or ""

    def _soft(getter):
        # A source that's down/signed-out must NOT kill the scan — we merge whatever
        # sources ARE up. (http_get fail()s hard via sys.exit on a dead gateway.)
        def g(path):
            try:
                return getter(path)
            except SystemExit:
                return None
            except Exception:
                return None
        return g

    # Sessions come from the ONE provider-quota plugin's /activity endpoint, which
    # aggregates the session store + tui_gateway logs + active-sessions registry
    # SERVER-SIDE (per provider). The client reads sessions from that single plugin
    # over the Desktop/gateway connection instead of scanning REST itself. An active
    # session gets a fresh last_active so the client lights it; model → colour.
    out = []
    status_busy = False
    act = _soft(get_json)("/api/plugins/provider-quota/activity") or {}
    for s in act.get("sessions") or []:
        active = bool(s.get("is_active"))
        if active:
            status_busy = True
        # A session can run MULTIPLE models — resolve each to its provider family
        # (distinct, in order) so the pet draws one dot split into a wedge per
        # model. Fall back to the single resolved provider when there's just one.
        families = []
        for m in (s.get("models") or []):
            fam = _dot_provider({"model": m})
            if fam and fam not in families:
                families.append(fam)
        if not families:
            fam = _dot_provider(s)
            families = [fam] if fam else []
        # Forward a WAITING-FOR-INPUT flag if the gateway reports one (e.g. a
        # permission / approval prompt). Accept a few likely field names / a
        # status string so the menu-bar can badge the session + wave the pet
        # without a false positive when the gateway doesn't report it.
        def _needs_input(sess):
            for k in ("needs_input", "waiting_for_input", "awaiting_input",
                      "awaiting_response", "needsInput", "input_required"):
                v = sess.get(k)
                if isinstance(v, bool):
                    return v
            st = str(sess.get("state") or sess.get("status") or "").lower()
            return st in ("waiting", "awaiting_input", "needs_input",
                          "input_required", "waiting_for_input", "awaiting_response")
        out.append({
            "is_active": active,
            "ended_at": s.get("ended_at"),
            "last_active": time.time() if active else s.get("last_active"),
            "billing_provider": _dot_provider(s),
            "provider": s.get("provider"),
            "providers": families,
            "needs_input": _needs_input(s),
        })
    emit(json.dumps({"agents": 0, "status_busy": status_busy, "sessions": out}).encode())
    sys.exit(0)

# --- Normal single-endpoint mode. ---
status, body = fetch(ENDPOINT)
if kind != "local" and status in (301, 302, 303, 307, 308, 401, 403):
    fail("Hermes Desktop session expired — open Hermes Desktop to refresh.")
if status != 200:
    fail(EXPIRED_MSG % status)
emit(body)
PY
