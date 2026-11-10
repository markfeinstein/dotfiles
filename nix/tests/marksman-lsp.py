"""Exercise the installed release executable, not a mocked language server."""

import json
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time


def check(executable):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / ".marksman.toml").write_text("")
        index = root / "index.md"
        target = root / "target.md"
        index.write_text("# Index\n\n[Target](target.md)\n")
        target.write_text("# Target\n")
        process = subprocess.Popen(
            [executable, "server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        responses = queue.Queue()

        def read_responses():
            try:
                while True:
                    headers = {}
                    while True:
                        line = process.stdout.readline()
                        if not line:
                            return
                        if line in (b"\r\n", b"\n"):
                            break
                        key, value = line.decode().split(":", 1)
                        headers[key.lower()] = value.strip()
                    length = int(headers["content-length"])
                    responses.put(json.loads(process.stdout.read(length)))
            except Exception as error:
                responses.put(error)

        def send(method, params=None, request_id=None):
            message = {"jsonrpc": "2.0", "method": method, "params": params}
            if request_id is not None:
                message["id"] = request_id
            body = json.dumps(message).encode()
            process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
            process.stdin.flush()

        def response(request_id):
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                message = responses.get(timeout=max(0.01, deadline - time.monotonic()))
                if isinstance(message, Exception):
                    raise message
                if message.get("id") == request_id:
                    assert "error" not in message, message
                    return message["result"]
            raise AssertionError(f"No LSP response for request {request_id}")

        threading.Thread(target=read_responses, daemon=True).start()
        try:
            send(
                "initialize",
                {
                    "processId": None,
                    "rootUri": root.as_uri(),
                    "capabilities": {},
                },
                1,
            )
            initialized = response(1)
            assert initialized["capabilities"]["definitionProvider"], initialized
            send("initialized", {})
            for document in (index, target):
                send(
                    "textDocument/didOpen",
                    {
                        "textDocument": {
                            "uri": document.as_uri(),
                            "languageId": "markdown",
                            "version": 1,
                            "text": document.read_text(),
                        }
                    },
                )
            send(
                "textDocument/definition",
                {
                    "textDocument": {"uri": index.as_uri()},
                    "position": {"line": 2, "character": 12},
                },
                2,
            )
            definitions = response(2)
            if isinstance(definitions, dict):
                definitions = [definitions]
            assert definitions, "Markdown link definition returned no locations"
            assert any(
                location.get("uri", location.get("targetUri")) == target.as_uri()
                for location in definitions
            ), definitions
            send("shutdown", None, 3)
            response(3)
            send("exit")
            assert process.wait(timeout=5) == 0, process.stderr.read().decode()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
        print("PASS: upstream Marksman resolves a Markdown link and exits cleanly")


if __name__ == "__main__":
    check(sys.argv[1])
