import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/test/requests.log"
counter = {"id": 0}


class Handler(BaseHTTPRequestHandler):
    def _read_body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            chunks = []
            while True:
                size_line = self.rfile.readline().strip()
                size = int(size_line.split(b";")[0], 16)
                if size == 0:
                    self.rfile.readline()  # trailing CRLF
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.readline()  # chunk CRLF
            return b"".join(chunks)
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length)

    def do_POST(self):
        body = self._read_body().decode("utf-8", "replace")
        try:
            payload = json.loads(body)
        except ValueError:
            payload = {"raw": body}

        query = payload.get("query", "")
        with open(LOG, "a") as f:
            f.write(json.dumps({
                "ts": time.time(),
                "path": self.path,
                "auth": self.headers.get("Authorization", ""),
                "payload": payload,
            }) + "\n")

        if "insert_reading_journal" in query:
            counter["id"] += 1
            response = {"data": {"insert_reading_journal": {"reading_journal": {"id": counter["id"]}}}}
        else:
            response = {"data": {}}

        out = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", 8181), Handler).serve_forever()
