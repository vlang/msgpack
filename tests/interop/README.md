# MessagePack interoperability harness

This harness checks that the V module and other MessagePack implementations understand each other: each of them encodes every case of a shared corpus, and every implementation decodes every encoding, in both directions. The peers are msgpack-python, Go (vmihailenco/msgpack), Rust (rmp and rmpv), JavaScript (@msgpack/msgpack) and C (msgpack-c).

It is not part of `v test`: it needs network access for its first run, and Python 3.11+, uv, Go, Cargo, Node/npm, a C compiler and CMake.

## Running it

```sh
# build the V adapter against the parent directory of this module, with V3 (new) or the old compiler (old)
bash build-v.sh "$(cd ../../.. && pwd)" new
# the low-level API (Packer/Unpacker), then encode[Value]/decode[Value]
bash run.sh --v-command 'python3 adapter.py v' --require-v
bash run.sh --v-command 'python3 adapter.py v-generic' --require-v
```

The first run builds the pinned dependencies; `bash setup.sh` rebuilds them. Downloads, caches, binaries and reports live in a temporary directory printed by `python3 paths.py`, outside the repository. Set `INTEROP_WORK_DIR` to choose another location outside the repository. Set `V` to select the V executable. `build-v.sh` also runs the typed tests of `native/generic_test.v`, which `v test` runs as well.

A nonzero exit status means an unexplained failure. `results/report.json`, in the work directory, lists the counts per direction, the failures, the unsupported cases and the representation differences between implementations. Without `--v-command` the report says V was not tested.

## Corpus

`corpus.py` generates the corpus; run it directly to print it as JSON lines of `{id,value,wire?}`. Values are described without loss:

| `t` | Additional fields |
| --- | --- |
| `nil` | none |
| `bool` | `v`: boolean |
| `int` | `v`: signed or unsigned decimal **string**, full MessagePack range |
| `f32`, `f64` | `bits`: big-endian IEEE bit pattern in hex |
| `str`, `bin` | `hex`: original bytes |
| `array` | `v`: list of tagged values |
| `map` | `v`: ordered list of `[key,value]` pairs, including arbitrary keys and duplicates |
| `ext` | `type`: signed type number, `hex`: payload |
| `timestamp` | `sec`: signed decimal string, `nsec`: integer |

The corpus covers the boundaries of every format family, including the 32-bit length headers (with small objects) and 65,536-byte str/bin/ext payloads. An optional `wire` gives a valid but non-minimal encoding, decoded by every implementation. It is a finite corpus, not a proof that all inputs are handled.

## Adapters

Each adapter is a process reading one JSON request per line on stdin and writing one response per line on stdout:

```json
{"op":"encode","value":{"t":"int","v":"18446744073709551615"}}
{"hex":"cfffffffffffffffff"}
{"op":"decode","hex":"01"}
{"value":{"t":"int","v":"1"}}
```

A failure is `{"error":"..."}`; `{"unsupported":"..."}` marks a limitation of the peer's data model, never a success. `python3 adapter.py <python|go|rust|js|c|v|v-generic>` starts one of them. Native libraries do all the MessagePack work: the adapters only convert the tagged descriptions.

## Known limitations of the peers

- Python has a single float type: float32 values come back as float64.
- JavaScript objects cannot hold arbitrary map keys or duplicate keys: those cases are reported as unsupported. Its float width is an encoder-wide option, so mixed float32/float64 trees are unsupported too. It uses `useBigInt64`, and timestamps go through an opaque extension codec, to keep full integer and nanosecond precision.
- Rust and JavaScript carry timestamps as extension -1 payloads, so they test the wire format rather than a date API.

Implementations may choose different formats for the same value (for instance float32 against float64, or uint 64 against int 64 for the same integer): the report lists these differences, which are not failures.

Dependency versions are pinned by the inline metadata of the Python adapter, the Go module sums, the Cargo and npm lockfiles, and the msgpack-c commit in `setup.sh`.
