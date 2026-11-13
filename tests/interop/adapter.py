#!/usr/bin/env python3
"""JSONL entry point: {op:encode,value:tagged} or {op:decode,hex:...}."""

import json, os, subprocess, sys
from common import tokens, from_tokens
from paths import ROOT, WORK

COMMANDS = {
    "python": ["uv", "run", "--offline", str(ROOT / "native/python_adapter.py")],
    "go": [str(WORK / "build/go-adapter")],
    "rust": [str(WORK / "rust-target/release/rust-adapter")],
    "js": ["node", str(WORK / "native/js_adapter.mjs")],
    "c": [str(WORK / "build/c-adapter")],
    "v": [os.environ.get("MSGPACK_V_ADAPTER", str(WORK / "build/v-adapter"))],
    "v-generic": [
        os.environ.get("MSGPACK_V_ADAPTER", str(WORK / "build/v-adapter")),
        "--generic",
    ],
}


class Adapter:
    def __init__(self, name):
        env = dict(os.environ, UV_CACHE_DIR=str(WORK / "cache/uv"))
        self.proc = subprocess.Popen(
            COMMANDS[name],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )

    def call(self, request):
        op = request["op"]
        line = (
            "E " + " ".join(tokens(request["value"]))
            if op == "encode"
            else "D " + request["hex"]
        )
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()
        reply = self.proc.stdout.readline()
        if not reply:
            raise RuntimeError("native adapter exited: " + str(self.proc.poll()))
        kind, _, body = reply.strip().partition(" ")
        if kind == "H":
            return {"hex": body}
        if kind == "V":
            return {"value": from_tokens(body.split())}
        if kind == "U":
            return {"unsupported": body}
        if kind == "X":
            return {"error": body}
        raise RuntimeError("invalid native response: " + reply[:200])

    def close(self):
        self.proc.stdin.close()
        self.proc.stdout.close()
        self.proc.wait(timeout=10)


if __name__ == "__main__":
    a = Adapter(sys.argv[1])
    try:
        for line in sys.stdin:
            try:
                answer = a.call(json.loads(line))
            except Exception as e:
                answer = {"error": str(e)}
            print(json.dumps(answer, separators=(",", ":")), flush=True)
    finally:
        a.close()
