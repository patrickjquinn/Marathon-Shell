# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Local HTTP server for tests/privacy.qml: serves /page (an image, a script
# and a frame on /ads/ and /tracker.js, one allowed image) and records each
# request's path and Sec-GPC header; /log returns the record as JSON.
import http.server
import json
import sys
SEEN = []


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/log":
            body = json.dumps(SEEN).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        SEEN.append({"path": self.path, "gpc": self.headers.get("Sec-GPC")})
        if self.path.startswith("/page"):
            body = b"<title>blk</title><img src='/ads/banner.png'><img src='/ok.png'><script src='/tracker.js'></script><iframe src='/ads/frame.html'></iframe>"
            ct = "text/html"
        else:
            body = b"x"
            ct = "text/plain"
        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
