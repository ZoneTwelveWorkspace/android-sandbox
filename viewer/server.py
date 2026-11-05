#!/usr/bin/env python3
"""AI View Browser: a local proxy between an AI client and the phone's MCP server.

It forwards MCP traffic unchanged, records each call in memory, and serves a page that explains the calls.
It binds to loopback only, and never stores or displays the Authorization header. See README.md.
"""
import argparse
import base64
import http.client
import json
import os
import threading
import time
import uuid
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
MAX_EVENTS = 500
MAX_IMAGES = 100
MAX_TEXT = 200_000
MAX_ARGS = 64_000
MAX_CAPTURE = 32_000_000
CAPTURE_DELAY = 0.7
STATE_TOOL = "android_get_screen_state"
IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
HOP_HEADERS = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer",
               "transfer-encoding", "upgrade", "host", "content-length"}
STATIC = {"/": ("index.html", "text/html; charset=utf-8"), "/app.js": ("app.js", "text/javascript; charset=utf-8"),
          "/tools.js": ("tools.js", "text/javascript; charset=utf-8"), "/style.css": ("style.css", "text/css; charset=utf-8")}
# Calls that only read. Anything else may change the screen, so the viewer takes a picture after it.
READ_ONLY = {STATE_TOOL, "android_find_nodes", "android_get_node_details", "android_get_clipboard", "android_list_apps",
             "android_list_files", "android_read_file", "android_list_storage_locations", "android_get_location",
             "android_list_cameras", "android_list_camera_photo_resolutions", "android_list_camera_video_resolutions",
             "android_wait_for_node", "android_wait_for_idle", "android_get_shared_content"}


def parse_messages(body, content_type):
    """Return the JSON-RPC messages in a JSON or server-sent-events body."""
    text = body.decode("utf-8", "replace")
    chunks = [text]
    if "text/event-stream" in content_type:
        chunks = []
        for block in text.replace("\r\n", "\n").split("\n\n"):
            data = [line[5:].lstrip() for line in block.split("\n") if line.startswith("data:")]
            if data:
                chunks.append("\n".join(data))
    messages = []
    for chunk in chunks:
        try:
            parsed = json.loads(chunk)
        except ValueError:
            continue
        messages.extend(parsed if isinstance(parsed, list) else [parsed])
    return [m for m in messages if isinstance(m, dict)]


class Store:
    """Recent calls and screenshots, held in memory only."""

    def __init__(self):
        self.lock = threading.Lock()
        self.events = []
        self.images = OrderedDict()
        self.tools = []
        self.rev = 0
        self.next_id = 0
        self.boot = uuid.uuid4().hex

    def begin(self, method, tool, args, source, for_event=None):
        encoded = json.dumps(args, ensure_ascii=False)
        if len(encoded) > MAX_ARGS:
            args = {"_truncated": encoded[:MAX_ARGS]}
        with self.lock:
            self.next_id += 1
            self.rev += 1
            event = {"id": self.next_id, "rev": self.rev, "ts": time.time(), "method": method, "tool": tool, "args": args,
                     "source": source, "forEvent": for_event, "status": "running", "ms": None, "error": None, "text": "",
                     "images": []}
            self.events.append(event)
            del self.events[:-MAX_EVENTS]
            return event

    def finish(self, event, message=None, error=None):
        text, images, is_error = "", [], False
        result = (message or {}).get("result")
        if message and "error" in message:
            error = str(message["error"].get("message", message["error"]))
        if isinstance(result, dict):
            is_error = bool(result.get("isError"))
            parts = []
            for item in result.get("content") or []:
                if item.get("type") == "text":
                    parts.append(str(item.get("text", "")))
                elif item.get("type") == "image" and item.get("mimeType") in IMAGE_TYPES:
                    images.append(self.add_image(item))
            text = "\n".join(parts)
            if "tools" in result:
                with self.lock:
                    self.tools = result["tools"]
            elif event["method"] != "tools/call":
                text = json.dumps(result, ensure_ascii=False, indent=1)
        with self.lock:
            self.rev += 1
            event.update(rev=self.rev, ms=round((time.time() - event["ts"]) * 1000), text=text[:MAX_TEXT], images=images,
                         error=error, status="error" if (error or is_error) else "ok")

    def add_image(self, item):
        try:
            data = base64.b64decode(item.get("data", ""), validate=False)
        except ValueError:
            return None
        image_id = uuid.uuid4().hex
        with self.lock:
            self.images[image_id] = (item["mimeType"], data)
            while len(self.images) > MAX_IMAGES:
                self.images.popitem(last=False)
        return image_id

    def since(self, rev):
        with self.lock:
            return {"boot": self.boot, "rev": self.rev, "tools": self.tools,
                    "events": [dict(e) for e in self.events if e["rev"] > rev]}


class Upstream:
    """The viewer's own MCP session, used only to read the screen and the tool list."""

    def __init__(self, port, token):
        self.port, self.token, self.session = port, token, None
        self.lock = threading.Lock()

    def _post(self, payload):
        headers = {"Authorization": "Bearer " + self.token, "Content-Type": "application/json",
                   "Accept": "application/json, text/event-stream"}
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        try:
            conn.request("POST", "/mcp", json.dumps(payload), headers)
            resp = conn.getresponse()
            body = resp.read()
            return resp.status, resp.getheader("Mcp-Session-Id"), resp.getheader("Content-Type", ""), body
        finally:
            conn.close()

    def _start_session(self):
        self.session = None
        status, session, _, _ = self._post({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "ai-view-browser", "version": "1"}}})
        if status != 200:
            raise OSError("MCP server answered HTTP %d" % status)
        self.session = session
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def call(self, method, params):
        with self.lock:
            if not self.token:
                raise OSError("no token")
            payload = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
            for attempt in (1, 2):
                if attempt == 2 or self.session is None:
                    self._start_session()
                status, _, content_type, body = self._post(payload)
                if status == 200:
                    break
                if attempt == 2:
                    raise OSError("MCP server answered HTTP %d" % status)
            found = [m for m in parse_messages(body, content_type) if m.get("id") == 1]
            if not found:
                raise OSError("MCP server sent no answer")
            return found[0]


class Capturer(threading.Thread):
    """Reads the screen after each action. When actions arrive quickly, only the newest gets a picture."""

    def __init__(self, store, upstream):
        super().__init__(daemon=True)
        self.store, self.upstream = store, upstream
        self.wake = threading.Event()
        self.pending = None
        self.has_pending = False

    def request(self, for_event=None):
        self.pending, self.has_pending = for_event, True
        self.wake.set()

    def run(self):
        while True:
            self.wake.wait()
            time.sleep(CAPTURE_DELAY)
            self.wake.clear()
            if not self.has_pending:
                continue
            for_event, self.has_pending = self.pending, False
            event = self.store.begin("tools/call", STATE_TOOL, {"include_screenshot": True}, "viewer", for_event)
            try:
                if not self.store.tools:
                    self.store.finish(self.store.begin("tools/list", None, {}, "viewer"), self.upstream.call("tools/list", {}))
                self.store.finish(event, self.upstream.call("tools/call", {"name": STATE_TOOL, "arguments": {"include_screenshot": True}}))
            except (OSError, http.client.HTTPException) as exc:
                self.store.finish(event, error=str(exc))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "AIViewBrowser"
    sys_version = ""

    def log_message(self, *_):
        pass  # Requests stay out of logs: they can hold typed text.

    def local_only(self):
        """Refuse requests from web pages on other origins, including through DNS rebinding."""
        allowed = {"127.0.0.1:%d" % self.server.opts.port, "localhost:%d" % self.server.opts.port}
        origin = self.headers.get("Origin")
        if self.headers.get("Host") in allowed and (not origin or origin.split("://", 1)[-1] in allowed):
            return True
        self.reply(403, "text/plain", b"forbidden")
        return False

    def reply(self, status, content_type, body, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def reply_json(self, value, status=200):
        self.reply(status, "application/json", json.dumps(value, ensure_ascii=False).encode())

    def do_GET(self):
        if not self.local_only():
            return
        url = urlparse(self.path)
        if url.path == "/mcp":
            return self.forward(b"")
        if url.path == "/favicon.ico":
            return self.reply(204, "image/x-icon", b"")
        if url.path in STATIC:
            name, content_type = STATIC[url.path]
            web = "http://127.0.0.1:%d" % self.server.opts.web_port
            csp = ("default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; "
                   "frame-src %s; base-uri 'none'; form-action 'none'" % web)
            return self.reply(200, content_type, (HERE / name).read_bytes(), {"Content-Security-Policy": csp})
        if url.path == "/api/meta":
            o = self.server.opts
            return self.reply_json({"name": o.name, "port": o.port, "webPort": o.web_port, "mcpPort": o.upstream_port})
        if url.path == "/api/events":
            since = parse_qs(url.query).get("since", ["0"])[0]
            return self.reply_json(self.server.store.since(int(since) if since.isdigit() else 0))
        if url.path.startswith("/api/image/"):
            with self.server.store.lock:
                image = self.server.store.images.get(url.path.rsplit("/", 1)[-1])
            if image:
                return self.reply(200, image[0], image[1])
        self.reply(404, "text/plain", b"not found")

    def do_POST(self):
        if not self.local_only():
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        path = urlparse(self.path).path
        if path == "/mcp":
            return self.forward(body)
        if path == "/api/refresh":
            self.server.capturer.request()
            return self.reply_json({"ok": True})
        self.reply(404, "text/plain", b"not found")

    def do_DELETE(self):
        if self.local_only():
            self.forward(b"")

    def record_requests(self, body):
        """Open an event for each request in the body, keyed by JSON-RPC id."""
        try:
            parsed = json.loads(body) if body else []
        except ValueError:
            return {}
        started = {}
        for message in parsed if isinstance(parsed, list) else [parsed]:
            if not isinstance(message, dict) or "id" not in message or "method" not in message:
                continue
            params = message.get("params") or {}
            is_call = message["method"] == "tools/call"
            started[str(message["id"])] = self.server.store.begin(
                message["method"], params.get("name") if is_call else None,
                (params.get("arguments") or {}) if is_call else params, "ai")
        return started

    def forward(self, body):
        started = self.record_requests(body)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS}
        conn = http.client.HTTPConnection("127.0.0.1", self.server.opts.upstream_port, timeout=300)
        try:
            conn.request(self.command, self.path, body or None, headers)
            resp = conn.getresponse()
        except (OSError, http.client.HTTPException) as exc:
            conn.close()
            for event in started.values():
                self.server.store.finish(event, error="手機的 MCP 連不上：%s" % exc)
            return self.reply(502, "text/plain", b"MCP server is not reachable")
        self.send_response(resp.status)
        for key, value in resp.getheaders():
            if key.lower() not in HOP_HEADERS:
                self.send_header(key, value)
        size = resp.getheader("Content-Length")
        self.send_header("Content-Length", size) if size else self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        captured, client_gone = bytearray(), False
        try:
            while True:
                chunk = resp.read1(65536)
                if not chunk:
                    break
                if started and len(captured) < MAX_CAPTURE:
                    captured += chunk
                if not client_gone:
                    try:
                        self.wfile.write(chunk if size else b"%x\r\n%s\r\n" % (len(chunk), chunk))
                        self.wfile.flush()
                    except OSError:
                        client_gone = True
                        if not started:
                            break
            if not size and not client_gone:
                self.wfile.write(b"0\r\n\r\n")
        except (OSError, http.client.HTTPException):
            pass
        finally:
            conn.close()
        if client_gone:
            self.close_connection = True
        self.finish_events(started, resp, captured)

    def finish_events(self, started, resp, captured):
        store = self.server.store
        answers = {str(m.get("id")): m for m in parse_messages(bytes(captured), resp.getheader("Content-Type", ""))}
        for key, event in started.items():
            if key in answers:
                store.finish(event, answers[key])
            else:
                store.finish(event, error="手機回覆 HTTP %d" % resp.status)
            if event["tool"] and event["tool"] not in READ_ONLY:
                self.server.capturer.request(event["id"])


class Server(ThreadingHTTPServer):
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=9765)
    parser.add_argument("--upstream-port", type=int, default=8765)
    parser.add_argument("--web-port", type=int, default=6080)
    parser.add_argument("--name", default="android-fc")
    opts = parser.parse_args()
    server = Server(("127.0.0.1", opts.port), Handler)
    server.opts, server.store = opts, Store()
    server.capturer = Capturer(server.store, Upstream(opts.upstream_port, os.environ.get("MCP_VIEW_TOKEN", "")))
    server.capturer.start()
    server.capturer.request()
    print("AI View Browser: http://127.0.0.1:%d/" % opts.port, flush=True)
    print("Connect your AI to:  http://127.0.0.1:%d/mcp  (same token as before)" % opts.port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
