#!/usr/bin/env python3
"""Generate valid conformance cases, with explicit wide-wire fixtures."""

import json


def generate():
    cases = []

    def add(name, v, **extra):
        cases.append(dict(id=name, value=v, **extra))

    def num(n):
        return {"t": "int", "v": str(n)}

    def text(s):
        return {"t": "str", "hex": s.encode().hex()}

    add("nil", {"t": "nil"})
    for b in (False, True):
        add("bool-" + str(b), {"t": "bool", "v": b})
    integers = {
        0,
        1,
        127,
        128,
        255,
        256,
        65535,
        65536,
        2**32 - 1,
        2**32,
        2**63 - 1,
        2**63,
        2**64 - 1,
        -1,
        -32,
        -33,
        -128,
        -129,
        -32768,
        -32769,
        -(2**31),
        -(2**31) - 1,
        -(2**63),
    }
    for n in sorted(integers):
        add("int-" + str(n), num(n))
    for t, bits in [
        ("f32", "00000000"),
        ("f32", "80000000"),
        ("f32", "3fc00000"),
        ("f32", "00000001"),
        ("f32", "7f800000"),
        ("f32", "ff800000"),
        ("f32", "7fc00000"),
        ("f64", "0000000000000000"),
        ("f64", "8000000000000000"),
        ("f64", "3ff8000000000000"),
        ("f64", "0000000000000001"),
        ("f64", "7ff0000000000000"),
        ("f64", "fff0000000000000"),
        ("f64", "7ff8000000000000"),
    ]:
        add(t + "-" + bits, {"t": t, "bits": bits})
    for n in (0, 1, 31, 32, 255, 256, 65535, 65536):
        add("str-" + str(n), text("a" * n))
    add("str-unicode", text('été 🌍 日本語\x00"\\\n'))
    for n in (0, 1, 255, 256, 65535, 65536):
        add(
            "bin-" + str(n),
            {"t": "bin", "hex": (bytes(range(256)) * (n // 256 + 1))[:n].hex()},
        )
    for n in (0, 1, 15, 16):
        add("array-" + str(n), {"t": "array", "v": [num(i) for i in range(n)]})
    for n in (0, 1, 15, 16):
        add(
            "map-" + str(n),
            {"t": "map", "v": [[text("k" + str(i)), num(i)] for i in range(n)]},
        )
    add("map-integer-key", {"t": "map", "v": [[num(7), text("seven")]]})
    add("map-array-key", {"t": "map", "v": [[{"t": "array", "v": [num(1)]}, num(2)]]})
    add("map-duplicate", {"t": "map", "v": [[text("x"), num(1)], [text("x"), num(2)]]})
    for n in (0, 1, 2, 3, 4, 8, 16, 17, 255, 256, 65535, 65536):
        add("ext-" + str(n), {"t": "ext", "type": 42, "hex": (b"\xab" * n).hex()})
    add("ext-127", {"t": "ext", "type": 127, "hex": "01"})
    for sec, ns in [
        (0, 0),
        (60, 0),
        (2**32 - 1, 0),
        (2**32, 0),
        (2**34 - 1, 999999999),
        (2**34, 0),
        (-1, 0),
        (-1, 999999999),
        (1, 123),
        (1, 999999999),
        (-(2**63), 0),
        (2**63 - 1, 0),
    ]:
        add(f"time-{sec}-{ns}", {"t": "timestamp", "sec": str(sec), "nsec": ns})
    add(
        "nested",
        {
            "t": "map",
            "v": [
                [
                    text("items"),
                    {
                        "t": "array",
                        "v": [num(1), {"t": "array", "v": [text("v"), {"t": "nil"}]}],
                    },
                ]
            ],
        },
    )
    # Larger legal descriptor widths can encode small values. No giant allocation is required.
    for name, wire, val in [
        ("str32-small", "db0000000161", text("a")),
        ("bin32-small", "c60000000161", {"t": "bin", "hex": "61"}),
        ("array32-small", "dd0000000101", {"t": "array", "v": [num(1)]}),
        ("map32-small", "df00000001a16101", {"t": "map", "v": [[text("a"), num(1)]]}),
        ("ext32-small", "c9000000012a01", {"t": "ext", "type": 42, "hex": "01"}),
        ("uint64-small", "cf0000000000000001", num(1)),
        ("int64-small", "d30000000000000001", num(1)),
    ]:
        add(name, val, wire=wire)
    return cases


if __name__ == "__main__":
    for case in generate():
        print(json.dumps(case, separators=(",", ":")))
