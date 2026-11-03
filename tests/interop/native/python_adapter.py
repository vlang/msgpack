# /// script
# requires-python = ">=3.11"
# dependencies = ["msgpack==1.1.1"]
# ///
import sys, struct, msgpack


class Pairs(list):
    pass


def enc(it):
    t = next(it)
    if t == "n":
        return msgpack.packb(None)
    if t == "b":
        return msgpack.packb(next(it) == "1")
    if t == "i":
        return msgpack.packb(int(next(it)))
    if t in ("f", "d"):
        v = struct.unpack(">f" if t == "f" else ">d", bytes.fromhex(next(it)))[0]
        return msgpack.packb(v, use_single_float=t == "f")
    if t in ("s", "x"):
        h = next(it)
        b = bytes.fromhex("" if h == "-" else h)
        return msgpack.packb(b.decode("utf8") if t == "s" else b, use_bin_type=True)
    if t in ("a", "m"):
        n = int(next(it))
        p = msgpack.Packer()
        return (
            p.pack_array_header(n) if t == "a" else p.pack_map_header(n)
        ) + b"".join(enc(it) for _ in range(n * (2 if t == "m" else 1)))
    if t == "e":
        tag = int(next(it))
        h = next(it)
        b = bytes.fromhex("" if h == "-" else h)
        v = msgpack.Timestamp.from_bytes(b) if tag == -1 else msgpack.ExtType(tag, b)
        return msgpack.packb(v)
    raise ValueError(t)


def out(v):
    if v is None:
        return ["n"]
    if isinstance(v, bool):
        return ["b", str(int(v))]
    if isinstance(v, int):
        return ["i", str(v)]
    if isinstance(v, float):
        return ["d", struct.pack(">d", v).hex()]
    if isinstance(v, str):
        return ["s", v.encode().hex() or "-"]
    if isinstance(v, bytes):
        return ["x", v.hex() or "-"]
    if isinstance(v, Pairs):
        return ["m", str(len(v))] + [t for pair in v for x in pair for t in out(x)]
    if isinstance(v, list):
        return ["a", str(len(v))] + [t for x in v for t in out(x)]
    if isinstance(v, msgpack.Timestamp):
        return ["e", "-1", v.to_bytes().hex()]
    if isinstance(v, msgpack.ExtType):
        return ["e", str(v.code), v.data.hex() or "-"]
    raise ValueError(type(v))


for line in sys.stdin:
    try:
        args = line.split()
        op = args.pop(0)
        if op == "E":
            it = iter(args)
            b = enc(it)
            if next(it, None) is not None:
                raise ValueError("extra tokens")
            print("H " + b.hex(), flush=True)
        elif op == "D":
            v = msgpack.unpackb(
                bytes.fromhex(args[0]),
                raw=False,
                strict_map_key=False,
                object_pairs_hook=Pairs,
                timestamp=0,
            )
            print("V " + " ".join(out(v)), flush=True)
        else:
            raise ValueError("unknown operation")
    except Exception as e:
        print("X " + str(e).replace("\n", " "), flush=True)
