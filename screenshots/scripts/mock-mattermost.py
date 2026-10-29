#!/usr/bin/env python3
"""Just enough of the Mattermost REST API for `netclaw config` to resolve channel labels.

The channel permissions screen looks channel IDs up through GET /api/v4/users/me, the bot's teams
and each team's channels. Nothing else is implemented, so this is a fixture for one screenshot
(config-channel-audiences.png), not a Mattermost server. Listens on 127.0.0.1:8065.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TEAM = "t4m1d9q2w6x8c3v5b7n1k0j2hz"
CHANNELS = [
    {"id": "c1a5s7i9s3t0a8n2t6b4o1t5k7", "name": "assistant", "display_name": "Assistant", "type": "O"},
    {"id": "c2o8p4s6r1o9o3m5d7e0m2o4k6", "name": "ops-room", "display_name": "Ops Room", "type": "O"},
    {"id": "c3l9u5n1c7h2t4a6b8l0e1d3k5", "name": "lunch", "display_name": "Lunch", "type": "O"},
]


class Handler(BaseHTTPRequestHandler):
    def _send(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/v4/users/me":
            self._send({"id": "u7b0t2i4d6n8e0t2c4l6a8w0ka", "username": "netclaw-bot"})
        elif path == "/api/v4/users/me/teams":
            self._send([{"id": TEAM, "name": "demo"}])
        elif path == f"/api/v4/users/me/teams/{TEAM}/channels":
            self._send(CHANNELS)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8065), Handler).serve_forever()
