#!/usr/bin/env python3
"""Bidirectional matrix. V plugs in via the same JSONL protocol as adapter.py."""

import argparse, collections, json, shlex, subprocess
from pathlib import Path
from adapter import Adapter
from paths import WORK
from common import semantic
from corpus import generate


class External:
    def __init__(self, command):
        self.proc = subprocess.Popen(
            shlex.split(command),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def call(self, req):
        self.proc.stdin.write(json.dumps(req, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("V adapter exited")
        return json.loads(line)

    def close(self):
        self.proc.stdin.close()
        self.proc.stdout.close()
        self.proc.wait(timeout=10)


def run():
    ap = argparse.ArgumentParser()
    ap.add_argument("--implementations", default="python,go,rust,js,c")
    ap.add_argument(
        "--v-command", help="V JSONL adapter command; absent means V remains NOT TESTED"
    )
    ap.add_argument(
        "--require-v",
        action="store_true",
        help="Fail unless both V directions are exercised",
    )
    ap.add_argument(
        "--v-encoded",
        type=Path,
        help="JSONL {id,hex} emitted by V for every case of corpus.py",
    )
    ap.add_argument("--out", type=Path, default=WORK / "results")
    args = ap.parse_args()
    if args.require_v and not args.v_command:
        ap.error("--require-v needs --v-command for both directions")
    args.out.mkdir(parents=True, exist_ok=True)
    cases = generate()
    byid = {c["id"]: c for c in cases}
    adapters = {name: Adapter(name) for name in args.implementations.split(",")}
    if args.v_command:
        adapters["v"] = External(args.v_command)
    counts = collections.Counter()
    differences = []
    errors = []
    limits = []
    wires = []

    def result(src, dst, case, reply):
        key = f"{src}->{dst}"
        if "unsupported" in reply:
            limits.append(
                {"direction": key, "id": case["id"], "reason": reply["unsupported"]}
            )
            counts[key + " unsupported"] += 1
            return
        if "value" not in reply:
            errors.append({"direction": key, "id": case["id"], "reply": reply})
            counts[key + " FAIL"] += 1
            return
        if semantic(reply["value"]) != semantic(case["value"]):
            errors.append(
                {
                    "direction": key,
                    "id": case["id"],
                    "actual": reply["value"],
                    "expected": case["value"],
                }
            )
            counts[key + " FAIL"] += 1
            return
        counts[key + " pass"] += 1
        if reply["value"] != case["value"]:
            differences.append(
                {
                    "direction": key,
                    "id": case["id"],
                    "kind": "host representation",
                    "actual_type": reply["value"]["t"],
                }
            )

    try:
        for name, a in adapters.items():
            rows = []
            for c in cases:
                reply = a.call({"op": "encode", "value": c["value"]})
                if "hex" in reply:
                    row = {"id": c["id"], "hex": reply["hex"]}
                    rows.append(row)
                    wires.append((name, c, reply["hex"]))
                    counts[name + " encode pass"] += 1
                elif "unsupported" in reply:
                    limits.append(
                        {
                            "direction": name + " encode",
                            "id": c["id"],
                            "reason": reply["unsupported"],
                        }
                    )
                    counts[name + " encode unsupported"] += 1
                else:
                    errors.append(
                        {"direction": name + " encode", "id": c["id"], "reply": reply}
                    )
                    counts[name + " encode FAIL"] += 1
            (args.out / (name + "-encoded.jsonl")).write_text(
                "".join(json.dumps(r) + "\n" for r in rows)
            )
        # Exercise legal wider headers separately from each library's preferred output.
        wires.extend(("fixture", c, c["wire"]) for c in cases if "wire" in c)
        if args.v_encoded:
            rows = [json.loads(s) for s in args.v_encoded.read_text().splitlines() if s]
            ids = [r["id"] for r in rows]
            if len(ids) != len(set(ids)):
                raise ValueError("duplicate ids in V results")
            missing = set(byid) - set(ids)
            if missing:
                raise ValueError(
                    "V results missing corpus cases: " + ",".join(sorted(missing))
                )
            wires.extend(("v-file", byid[r["id"]], r["hex"]) for r in rows)
        for source, c, wire in wires:
            for dest, a in adapters.items():
                result(source, dest, c, a.call({"op": "decode", "hex": wire}))
        bycase = collections.defaultdict(dict)
        for name, c, w in wires:
            if name not in ("fixture", "v-file"):
                bycase[c["id"]][name] = w
        for cid, rows in bycase.items():
            if len(set(rows.values())) > 1:
                differences.append(
                    {
                        "id": cid,
                        "kind": "wire choices",
                        "sizes": {k: len(v) // 2 for k, v in rows.items()},
                        "prefixes": {k: v[:24] for k, v in rows.items()},
                    }
                )
    finally:
        for a in adapters.values():
            a.close()
    report = {
        "cases": len(cases),
        "v_status": "tested"
        if args.v_command
        else "decode-by-peers only"
        if args.v_encoded
        else "NOT TESTED",
        "counts": dict(sorted(counts.items())),
        "failures": errors,
        "limitations": limits,
        "differences": differences,
    }
    (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        json.dumps(
            {
                "cases": len(cases),
                "v_status": report["v_status"],
                "failures": len(errors),
                "limitations": len(limits),
                "differences": len(differences),
                "counts": report["counts"],
            },
            indent=2,
        )
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(run())
