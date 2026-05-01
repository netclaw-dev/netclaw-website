"""Lightweight demo MCP server for screenshot capture.

Exposes a handful of representative tools so the netclaw MCP tools TUI
has something meaningful to display in documentation screenshots.
"""

from datetime import datetime, timezone
from mcp.server.fastmcp import FastMCP

app = FastMCP("demo-utilities", host="0.0.0.0", port=8080)


@app.tool()
def get_current_time(timezone_name: str = "UTC") -> str:
    """Get the current date and time in UTC."""
    return datetime.now(timezone.utc).isoformat()


@app.tool()
def calculate(expression: str) -> str:
    """Evaluate a mathematical expression safely."""
    allowed = set("0123456789+-*/.() ")
    if not all(c in allowed for c in expression):
        return "Error: invalid characters"
    return str(eval(expression))  # noqa: S307 — demo only


@app.tool()
def lookup_dns(hostname: str) -> str:
    """Resolve a hostname to its IP addresses."""
    import socket
    try:
        results = socket.getaddrinfo(hostname, None)
        addrs = sorted({r[4][0] for r in results})
        return "\n".join(addrs)
    except socket.gaierror as e:
        return f"DNS lookup failed: {e}"


@app.tool()
def http_fetch(url: str, method: str = "GET") -> str:
    """Fetch a URL and return the response status and headers."""
    import urllib.request
    req = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(req, timeout=10) as resp:  # noqa: S310
        headers = dict(resp.headers)
        return f"Status: {resp.status}\nHeaders: {headers}"


@app.tool()
def generate_uuid() -> str:
    """Generate a random UUID v4."""
    import uuid
    return str(uuid.uuid4())


@app.tool()
def base64_encode(text: str) -> str:
    """Encode text as base64."""
    import base64
    return base64.b64encode(text.encode()).decode()


@app.tool()
def base64_decode(encoded: str) -> str:
    """Decode a base64-encoded string."""
    import base64
    return base64.b64decode(encoded).decode()


@app.tool()
def hash_text(text: str, algorithm: str = "sha256") -> str:
    """Hash text using the specified algorithm (md5, sha1, sha256, sha512)."""
    import hashlib
    h = hashlib.new(algorithm)
    h.update(text.encode())
    return h.hexdigest()


@app.tool()
def json_format(json_string: str) -> str:
    """Pretty-print a JSON string."""
    import json
    return json.dumps(json.loads(json_string), indent=2)


@app.tool()
def word_count(text: str) -> str:
    """Count words, characters, and lines in text."""
    words = len(text.split())
    chars = len(text)
    lines = text.count("\n") + 1
    return f"Words: {words}, Characters: {chars}, Lines: {lines}"


if __name__ == "__main__":
    app.run(transport="streamable-http")
