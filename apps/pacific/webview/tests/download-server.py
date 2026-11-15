# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Local HTTP server for tests/downloads.qml (started by the caller):
#
#   python3 tests/download-server.py 18090 DIR &
#
# Empties DIR and claims "report-final.bin" in it, as an empty file, the
# way an app reserves a name before the engine writes (Pacific does). /file
# is a 10 000-byte attachment named "report-final.bin"; /size?name=N returns
# the size of DIR/N, or -1 when it does not exist.
import http.server
import os
import shutil
import sys
import urllib.parse

NAME = "report-final.bin"
BODY = b"0123456789" * 1000


class H(http.server.BaseHTTPRequestHandler):
    def reply(self, body, headers):
        self.send_response(200)
        for k, v in headers.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/file":
            self.reply(BODY, {"Content-Type": "application/octet-stream",
                              "Content-Disposition": f'attachment; filename="{NAME}"'})
        elif url.path == "/size":
            name = urllib.parse.parse_qs(url.query).get("name", [""])[0]
            path = os.path.join(DIR, os.path.basename(name))
            size = os.path.getsize(path) if os.path.exists(path) else -1
            self.reply(str(size).encode(), {"Content-Type": "text/plain"})
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    DIR = sys.argv[2]
    shutil.rmtree(DIR, ignore_errors=True)
    os.makedirs(DIR)
    open(os.path.join(DIR, NAME), "wb").close()
    http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
