"""Lossless JSON corpus <-> small native-adapter transport. No msgpack decoder here."""

import struct


def timestamp_bytes(sec, ns):
    if not -(1 << 63) <= sec < (1 << 63) or not 0 <= ns < 1_000_000_000:
        raise ValueError("timestamp out of range")
    if 0 <= sec < (1 << 34):
        packed = (ns << 34) | sec
        if packed <= 0xFFFFFFFF:
            return struct.pack(">I", packed)
        return struct.pack(">Q", packed)
    return struct.pack(">Iq", ns, sec)


def timestamp_value(data):
    if len(data) == 4:
        sec, ns = int.from_bytes(data, "big"), 0
    elif len(data) == 8:
        n = int.from_bytes(data, "big")
        sec, ns = n & ((1 << 34) - 1), n >> 34
    elif len(data) == 12:
        ns, sec = struct.unpack(">Iq", data)
    else:
        raise ValueError("invalid timestamp length")
    if ns >= 1_000_000_000:
        raise ValueError("invalid timestamp nanoseconds")
    return {"t": "timestamp", "sec": str(sec), "nsec": ns}


def tokens(v):
    t = v["t"]
    if t == "nil":
        return ["n"]
    if t == "bool":
        return ["b", "1" if v["v"] else "0"]
    if t == "int":
        return ["i", v["v"]]
    if t in ("f32", "f64"):
        return ["f" if t == "f32" else "d", v["bits"]]
    if t in ("str", "bin"):
        return ["s" if t == "str" else "x", v["hex"] or "-"]
    if t == "array":
        return ["a", str(len(v["v"]))] + [s for x in v["v"] for s in tokens(x)]
    if t == "map":
        return ["m", str(len(v["v"]))] + [
            s for pair in v["v"] for x in pair for s in tokens(x)
        ]
    if t == "ext":
        return ["e", str(v["type"]), v["hex"] or "-"]
    if t == "timestamp":
        return ["e", "-1", timestamp_bytes(int(v["sec"]), v["nsec"]).hex()]
    raise ValueError("unknown corpus type: " + t)


def from_tokens(parts):
    it = iter(parts)

    def read():
        t = next(it)
        if t == "n":
            return {"t": "nil"}
        if t == "b":
            return {"t": "bool", "v": next(it) == "1"}
        if t == "i":
            return {"t": "int", "v": str(int(next(it)))}
        if t in ("f", "d"):
            return {"t": "f32" if t == "f" else "f64", "bits": next(it).lower()}
        if t in ("s", "x"):
            h = next(it)
            return {
                "t": "str" if t == "s" else "bin",
                "hex": "" if h == "-" else h.lower(),
            }
        if t == "a":
            return {"t": "array", "v": [read() for _ in range(int(next(it)))]}
        if t == "m":
            return {"t": "map", "v": [[read(), read()] for _ in range(int(next(it)))]}
        if t == "e":
            tag, h = int(next(it)), next(it)
            h = "" if h == "-" else h.lower()
            return (
                timestamp_value(bytes.fromhex(h))
                if tag == -1
                else {"t": "ext", "type": tag, "hex": h}
            )
        raise ValueError("unknown token: " + t)

    value = read()
    if next(it, None) is not None:
        raise ValueError("trailing transport tokens")
    return value


def semantic(v):
    """Comparison keeps maps/pairs and str/bin distinct; IEEE NaN payload isn't portable."""
    t = v["t"]
    if t in ("f32", "f64"):
        n = struct.unpack(">f" if t == "f32" else ">d", bytes.fromhex(v["bits"]))[0]
        return ("float", "nan" if n != n else n.hex())
    if t == "array":
        return (t, tuple(map(semantic, v["v"])))
    if t == "map":
        return (t, tuple((semantic(k), semantic(x)) for k, x in v["v"]))
    return tuple(sorted(v.items()))
