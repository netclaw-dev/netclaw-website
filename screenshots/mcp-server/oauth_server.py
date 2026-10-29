"""OAuth-protected demo MCP server for testing `netclaw mcp auth`.

One process plays both roles: the MCP resource server at /mcp and a minimal
OAuth 2.1 authorization server (authorization code + PKCE, refresh tokens with
rotation). The authorize endpoint auto-approves, so a script can follow the
redirect with curl instead of a browser.

MODE (environment variable):
  confidential  Pre-registered client only. No dynamic registration. The token
                endpoint rejects a wrong or missing client secret.
  public        Dynamic client registration (RFC 7591), public client, PKCE only.
  anonymous     Like public, but initialize and tools/list work without a token.
                Only tools/call returns 401 (models servers that allow anonymous
                catalog discovery).

Other settings: BASE_URL (public URL of this server), CLIENT_ID, CLIENT_SECRET,
TOKEN_TTL (access token lifetime in seconds, default 3600).
"""

import base64
import hashlib
import json
import os
import secrets
import time
from urllib.parse import urlencode

import uvicorn
from mcp.server.fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import JSONResponse, RedirectResponse, Response

MODE = os.environ.get("MODE", "confidential")
BASE_URL = os.environ.get("BASE_URL", "http://localhost:8080").rstrip("/")
CLIENT_ID = os.environ.get("CLIENT_ID", "demo-client")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET", "demo-secret")
TOKEN_TTL = int(os.environ.get("TOKEN_TTL", "3600"))

mcp = FastMCP("oauth-demo", stateless_http=True, host="0.0.0.0", port=8080)


@mcp.tool()
def whoami() -> str:
    """Return the identity this server associates with the access token."""
    return "demo-user"


@mcp.tool()
def generate_uuid() -> str:
    """Generate a random UUID v4."""
    import uuid
    return str(uuid.uuid4())


@mcp.prompt()
def review_checklist(topic: str) -> str:
    """Walk through a short review checklist for a topic."""
    return f"Review {topic}: list the risks, the owner of each risk, and the next action."


codes: dict[str, dict] = {}
access_tokens: dict[str, float] = {}
refresh_tokens: dict[str, dict] = {}
dynamic_clients: dict[str, dict] = {}


def log(msg: str) -> None:
    print(f"[oauth-demo] {msg}", flush=True)


def metadata_url() -> str:
    return f"{BASE_URL}/.well-known/oauth-protected-resource/mcp"


@mcp.custom_route("/.well-known/oauth-protected-resource/mcp", ["GET"])
@mcp.custom_route("/.well-known/oauth-protected-resource", ["GET"])
async def protected_resource(_: Request) -> Response:
    return JSONResponse({
        "resource": f"{BASE_URL}/mcp",
        "authorization_servers": [BASE_URL],
        "bearer_methods_supported": ["header"],
    })


@mcp.custom_route("/.well-known/oauth-authorization-server", ["GET"])
async def as_metadata(_: Request) -> Response:
    doc = {
        "issuer": BASE_URL,
        "authorization_endpoint": f"{BASE_URL}/authorize",
        "token_endpoint": f"{BASE_URL}/token",
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported":
            ["client_secret_post", "client_secret_basic"] if MODE == "confidential" else ["none"],
    }
    if MODE != "confidential":
        doc["registration_endpoint"] = f"{BASE_URL}/register"
    return JSONResponse(doc)


@mcp.custom_route("/register", ["POST"])
async def register(request: Request) -> Response:
    if MODE == "confidential":
        return JSONResponse({"error": "registration_not_supported"}, status_code=404)
    body = await request.json()
    client_id = "dyn-" + secrets.token_hex(6)
    dynamic_clients[client_id] = {"redirect_uris": body.get("redirect_uris", [])}
    log(f"registered dynamic client {client_id}")
    return JSONResponse({
        "client_id": client_id,
        "redirect_uris": body.get("redirect_uris", []),
        "token_endpoint_auth_method": "none",
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
    }, status_code=201)


def known_client(client_id: str, redirect_uri: str) -> bool:
    if MODE == "confidential":
        return client_id == CLIENT_ID and redirect_uri.endswith("/api/mcp/oauth/callback")
    return client_id in dynamic_clients and redirect_uri in dynamic_clients[client_id]["redirect_uris"]


@mcp.custom_route("/authorize", ["GET"])
async def authorize(request: Request) -> Response:
    q = request.query_params
    client_id, redirect_uri = q.get("client_id", ""), q.get("redirect_uri", "")
    if not known_client(client_id, redirect_uri):
        log(f"authorize rejected: unknown client {client_id} or redirect {redirect_uri}")
        return JSONResponse({"error": "invalid_request",
                             "error_description": "unknown client or redirect_uri"}, status_code=400)
    if not q.get("code_challenge"):
        return JSONResponse({"error": "invalid_request", "error_description": "PKCE required"}, status_code=400)
    code = secrets.token_urlsafe(16)
    codes[code] = {"client_id": client_id, "redirect_uri": redirect_uri,
                   "challenge": q["code_challenge"], "scope": q.get("scope", "")}
    log(f"authorize ok for {client_id}, scope='{q.get('scope', '')}'")
    params = {"code": code}
    if q.get("state"):
        params["state"] = q["state"]
    return RedirectResponse(f"{redirect_uri}?{urlencode(params)}", status_code=302)


def client_credentials(request: Request, form: dict) -> tuple[str, str | None]:
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("basic "):
        raw = base64.b64decode(auth[6:]).decode()
        cid, _, sec = raw.partition(":")
        return cid, sec
    return form.get("client_id", ""), form.get("client_secret")


@mcp.custom_route("/token", ["POST"])
async def token(request: Request) -> Response:
    form = dict((await request.form()).items())
    cid, sec = client_credentials(request, form)
    grant = form.get("grant_type")
    log(f"token request grant={grant} client={cid} secret_presented={sec is not None}")
    if MODE == "confidential" and (cid != CLIENT_ID or sec != CLIENT_SECRET):
        return JSONResponse({"error": "invalid_client",
                             "error_description": "client authentication failed"}, status_code=401)
    if grant == "authorization_code":
        info = codes.pop(form.get("code", ""), None)
        if info is None or info["client_id"] != cid:
            return JSONResponse({"error": "invalid_grant"}, status_code=400)
        verifier = form.get("code_verifier", "")
        digest = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        if digest != info["challenge"]:
            return JSONResponse({"error": "invalid_grant", "error_description": "PKCE mismatch"}, status_code=400)
        return issue(cid, info["scope"])
    if grant == "refresh_token":
        info = refresh_tokens.pop(form.get("refresh_token", ""), None)
        if info is None or info["client_id"] != cid:
            log("refresh rejected: unknown or already-used refresh token")
            return JSONResponse({"error": "invalid_grant"}, status_code=400)
        return issue(cid, info["scope"])
    return JSONResponse({"error": "unsupported_grant_type"}, status_code=400)


def issue(client_id: str, scope: str) -> Response:
    access = "at-" + secrets.token_urlsafe(16)
    refresh = "rt-" + secrets.token_urlsafe(16)
    access_tokens[access] = time.time() + TOKEN_TTL
    refresh_tokens[refresh] = {"client_id": client_id, "scope": scope}
    log(f"issued access token (ttl {TOKEN_TTL}s) and refresh token")
    return JSONResponse({"access_token": access, "token_type": "Bearer", "expires_in": TOKEN_TTL,
                         "refresh_token": refresh, "scope": scope})


def valid_bearer(headers: dict) -> bool:
    auth = headers.get(b"authorization", b"").decode()
    if not auth.lower().startswith("bearer "):
        return False
    expires = access_tokens.get(auth[7:])
    return expires is not None and expires > time.time()


class Gate:
    """Return 401 with an RFC 9728 challenge when /mcp has no valid bearer token."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["path"].rstrip("/") != "/mcp":
            return await self.app(scope, receive, send)

        headers = dict(scope["headers"])
        body = b""
        while True:
            message = await receive()
            body += message.get("body", b"")
            if not message.get("more_body"):
                break

        methods = []
        try:
            parsed = json.loads(body) if body else {}
            methods = [m.get("method") for m in (parsed if isinstance(parsed, list) else [parsed])]
        except ValueError:
            pass

        needs_token = MODE != "anonymous" or "tools/call" in methods
        ok = valid_bearer(headers)
        log(f"/mcp {scope['method']} methods={methods} bearer_valid={ok}")
        if needs_token and not ok:
            resp = Response(status_code=401, headers={
                "WWW-Authenticate": f'Bearer resource_metadata="{metadata_url()}"'})
            return await resp(scope, receive, send)

        replayed = False

        async def replay():
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        return await self.app(scope, replay, send)


if __name__ == "__main__":
    log(f"mode={MODE} base_url={BASE_URL}")
    uvicorn.run(Gate(mcp.streamable_http_app()), host="0.0.0.0", port=8080, log_level="warning")
