# msgpack

A [MessagePack](https://msgpack.org) encoder and decoder for V. MessagePack is a serialization
format with the data model of JSON, written in a compact binary form.

- Implements the whole [specification](https://github.com/msgpack/msgpack/blob/master/spec.md):
  every format, extension types and the timestamp extension.
- Exchanges data with the implementations of other languages: it is tested against Python, Go,
  Rust, JavaScript and C.
- Encodes and decodes V structs, arrays, maps, enums, Options and `time.Time` directly.
- Safe on untrusted input: malformed or truncated data returns an error instead of crashing.

## Installation

```sh
v install --git https://github.com/vlang/msgpack
```

## Quick start

```v
import msgpack

struct User {
	name  string
	age   int
	email ?string
	tags  []string
}

fn main() {
	user := User{
		name: 'Ada'
		age:  36
		tags: ['admin']
	}
	data := msgpack.encode(user)!
	println(data.hex())

	back := msgpack.decode[User](data)!
	assert back == user
}
```

`encode` returns a `[]u8`, `decode` reads one value back into the type you give it. Both return
an error rather than panic: handle it with `!` or `or { ... }`.

## Types

| V type | MessagePack | Notes |
| --- | --- | --- |
| `bool` | bool | |
| `int`, `i8`...`i64`, `u8`...`u64` | int | the smallest format that holds the value |
| `f32`, `f64` | float 32, float 64 | |
| `string` | str | |
| `[]u8` | bin | |
| arrays, fixed arrays | array | |
| maps | map | with any key type V maps accept |
| structs | map | field names as keys; see the attributes below |
| enums | int | or the member name with `enum_as_string: true` |
| `?T` | nil when `none` | struct fields, and values to encode |
| `time.Time` | timestamp extension | with nanoseconds, in UTC |
| type aliases | as their base type | |
| `msgpack.Value` | any value | for data whose shape is not known in advance |

Decoding converts between compatible types: any integer format into any V integer type that holds
the value, str into `[]u8` and bin into `string`, and an enum from its integer value or its name.
An integer that does not fit returns an error, it is never truncated. A float 64 decoded into an
`f32` is rounded, and becomes infinite beyond the range of `f32`. Using a type the module cannot
represent, such as a sum type, is a compile-time error.

## Struct attributes

```v
import msgpack

@[msgpack_rename_all: 'camelCase']
struct Account {
	id        int    @[msgpack: 'ID']
	username  string @[required]
	password  string @[skip]
	nickname  string @[omitempty]
	last_seen ?i64   @[omitempty]
}

fn main() {
	data := msgpack.encode(Account{ id: 1, username: 'ada', password: 'secret' })!
	// {"ID": 1, "username": "ada"}
	println(msgpack.decode_to_json(data)!)
}
```

| Attribute | Effect |
| --- | --- |
| `@[msgpack: 'name']` | uses another key (`@[codec: 'name']` works too) |
| `@[skip]`, `@[msgpack: '-']` | leaves the field out |
| `@[omitempty]` | leaves the field out when it is none, zero, false or empty |
| `@[required]` | decoding fails if the field is missing |
| `@[msgpack_rename_all: 'camelCase']` | on the struct: renames every field |
| `@[msgpack_as_array]` | on the struct: writes the fields as an array, in order |

`msgpack_rename_all` also accepts `PascalCase`, `kebab-case` and `SCREAMING_SNAKE_CASE`.
`@[msgpack_as_array]` gives a more compact encoding, and matches the default of Rust's
rmp-serde. When decoding a struct, keys that match no field are skipped.

## Errors

Decoding errors are typed, and tell where the problem is:

```v
import msgpack

struct Point {
	x f64
	y f64
}

fn main() {
	data := msgpack.encode({
		'x': 'one'
	})!
	msgpack.decode[Point](data) or {
		// msgpack: x: expected float, got str at offset 3
		println(err)
		if err is msgpack.TypeMismatchError {
			println(err.path) // x
		}
	}
}
```

The error types are `UnexpectedEofError`, `MalformedError`, `TypeMismatchError`, `IntRangeError`,
`MaxDepthError`, `UnknownFieldError`, `MissingFieldError`, `DuplicateKeyError` and
`InvalidUtf8Error`.

## Options

`encode` and `decode` take options as named arguments:

```v
import msgpack

fn main() {
	scores := {
		'bob': 2
		'ada': 1
	}
	data := msgpack.encode(scores, sort_keys: true)!
	back := msgpack.decode[map[string]int](data, deny_duplicate_keys: true)!
	println(back)
}
```

| `EncodeOpts` | Default | |
| --- | --- | --- |
| `sort_keys` | `false` | writes map entries with string or number keys in ascending order |
| `enum_as_string` | `false` | writes enums as their member name (except flag enums) |
| `initial_cap` | `128` | initial buffer capacity, in bytes |

| `DecodeOpts` | Default | |
| --- | --- | --- |
| `max_depth` | `256` | maximum nesting of arrays and maps |
| `validate_utf8` | `true` | rejects str values that are not valid UTF-8 |
| `deny_unknown_fields` | `false` | fails on keys that match no struct field |
| `deny_duplicate_keys` | `false` | fails when a map repeats a key |
| `allow_trailing_bytes` | `false` | ignores data after the first value |
| `max_buffer_size` | 100 MiB | largest value a `StreamDecoder` buffers |

## Dynamic data

When the shape of the data is not known in advance, decode it into a `msgpack.Value`:

```v
import msgpack

fn main() {
	data := msgpack.encode({
		'name': 'Ada'
		'age':  '36'
	})!
	v := msgpack.decode[msgpack.Value](data)!
	if name := v.get('name') {
		println(name.as_str() or { '' })
	}
	println(v.to_json()!)
}
```

`Value` holds any MessagePack value. Its maps keep their order, duplicate keys and keys of any
type.

`to_json` and `decode_to_json` convert MessagePack to JSON, and `encode_to_json` a V value through
its MessagePack encoding. Types JSON lacks are written as
follows: bin as a base64 string, an extension as `{"type": <type>, "data": <base64>}`, a
timestamp as an RFC 3339 string (for the years 1 to 9999), and a map key that is not a string as
the JSON text of the key. Values JSON cannot represent return an error: NaN and infinite floats,
str values that are not valid UTF-8, and keys that collide once converted.

## Extension types

A type chooses its own representation by implementing `Marshaler` and `Unmarshaler`, for instance
to be written as an extension type:

```v
import msgpack

struct Uuid {
mut:
	bytes []u8
}

pub fn (id Uuid) to_msgpack(mut p msgpack.Packer) ! {
	p.pack_ext(1, id.bytes)!
}

pub fn (mut id Uuid) from_msgpack(mut u msgpack.Unpacker) ! {
	ext := u.unpack_ext()!
	if ext.type_id != 1 || ext.data.len != 16 {
		return error('not a UUID')
	}
	id.bytes = ext.data
}

fn main() {
	id := Uuid{
		bytes: []u8{len: 16, init: u8(index)}
	}
	data := msgpack.encode(id)!
	assert msgpack.decode[Uuid](data)!.bytes == id.bytes
}
```

Other extensions decode to `msgpack.Ext`, and timestamps to `msgpack.Timestamp` or `time.Time`.
`msgpack.RawMessage` keeps an encoded value as is, to decode it later or pass it through.

## Low-level API

`Packer` and `Unpacker` write and read one value at a time, for full control over the output. A
`Packer` can be reset and reused, to encode many messages without allocating.

```v
import msgpack

fn main() {
	mut p := msgpack.new_packer()
	p.pack_array_header(3)
	p.pack_int(-1)
	p.pack_str('two')!
	p.pack_bool(true)

	mut u := msgpack.new_unpacker(p.bytes())
	n := u.unpack_array_header()!
	a := u.unpack_int()!
	b := u.unpack_str()!
	c := u.unpack_bool()!
	println('${n} ${a} ${b} ${c}')
}
```

## Streams

`StreamEncoder` and `StreamDecoder` write and read consecutive values on an `io.Writer` or an
`io.Reader`, such as a file or a network connection:

```v
import io
import msgpack
import os

struct Event {
	id   int
	name string
}

fn main() {
	path := os.join_path(os.temp_dir(), 'events.msgpack')
	mut output := os.create(path)!
	mut encoder := msgpack.new_stream_encoder(output)
	for i in 0 .. 3 {
		encoder.encode(Event{i, 'event ${i}'})!
	}
	output.close()

	mut input := os.open(path)!
	mut decoder := msgpack.new_stream_decoder(input)
	for {
		event := decoder.decode[Event]() or {
			if err is io.Eof {
				break
			}
			panic(err)
		}
		println(event.name)
	}
	input.close()
}
```

The decoder returns each value as soon as it is complete, without waiting for more data.

## Conformance and interoperability

- The tests decode every encoding of the
  [msgpack-test-suite](https://github.com/kawanet/msgpack-test-suite) dataset.
- [tests/interop](tests/interop) checks, in both directions, that this module and msgpack-python,
  Go (vmihailenco/msgpack), Rust (rmp), JavaScript (@msgpack/msgpack) and C (msgpack-c) decode
  each other's encodings.
- Values are written in their most compact format, as the specification recommends. Floats keep
  their V type: an `f64` is always written as a float 64.

## Performance

`examples/bench_msgpack_json_vs_json2.v` compares this module with the `encoding.cbor` and `json2`
modules of vlib:

```sh
v -prod run examples/bench_msgpack_json_vs_json2.v
```
