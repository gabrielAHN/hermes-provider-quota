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
        with _opener.open(req, timeout=20) as resp:
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

# --- Local backend: hit the loopback gateway the Desktop runs (a loopback bind
# needs no auth), discovered from backend-ownership.json. ---
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
    status, body = http_get(local_url + ENDPOINT, {"Accept": "*/*"})
    if status == 200:
        emit(body)
        sys.exit(0)
    fail("Local Hermes gateway returned HTTP %s." % status)

# --- Remote gateway: authenticate with the Desktop's OAuth session. ---
if not url:
    fail("Hermes Desktop has no gateway configured.")

tokens = read_json("native-oauth-tokens.json")
if tokens is None:
    fail("Sign in to Hermes Desktop.")


def _norm(value):
    return value.strip().strip("/")


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

status, body = http_get(
    url + ENDPOINT,
    {"Authorization": "Bearer " + access_token, "Accept": "*/*"},
)
if status in (301, 302, 303, 307, 308, 401, 403):
    fail("Hermes Desktop session expired — open Hermes Desktop to refresh.")
if status != 200:
    fail("Hermes gateway returned HTTP %s." % status)
emit(body)
PY
