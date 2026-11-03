module main

import encoding.hex
import math
import msgpack

fn test_decode_to_json_array() {
	assert msgpack.decode_to_json(msgpack.encode([1, 2])!)! == '[1,2]'
	assert msgpack.decode_to_json(msgpack.encode([[1, 2], [3]])!)! == '[[1,2],[3]]'
}

fn test_decode_to_json_map() {
	src := msgpack.encode({
		'key1': 1
		'key2': 2
	})!
	assert msgpack.decode_to_json(src)! == '{"key1":1,"key2":2}'
}

fn test_decode_to_json_scalars() {
	assert msgpack.decode_to_json(hex.decode('c0')!)! == 'null'
	assert msgpack.decode_to_json(hex.decode('c3')!)! == 'true'
	assert msgpack.decode_to_json(msgpack.encode(-5)!)! == '-5'
	assert msgpack.decode_to_json(msgpack.encode(max_u64)!)! == '18446744073709551615'
	assert msgpack.decode_to_json(msgpack.encode(1.5)!)! == '1.5'
}

fn test_decode_to_json_escapes_strings() {
	assert msgpack.decode_to_json(msgpack.encode('a"b\\c\nd\x01é')!)! == '"a\\"b\\\\c\\nd\\u0001é"'
}

fn test_decode_to_json_types_without_json_equivalent() {
	assert msgpack.decode_to_json(msgpack.encode([u8(1), 2, 3])!)! == '"AQID"'
	assert msgpack.decode_to_json(hex.decode('d40110')!)! == '{"type":1,"data":"EA=="}'
	assert msgpack.decode_to_json(hex.decode('d7ffa1dcd7c85a4af6a5')!)! == '"2018-01-02T03:04:05.678901234Z"'
	// {1: "a", nil: "b"}
	assert msgpack.decode_to_json(hex.decode('8201a161c0a162')!)! == '{"1":"a","null":"b"}'
}

fn test_decode_to_json_rejects_what_json_cannot_represent() {
	if _ := msgpack.decode_to_json(msgpack.encode(math.nan())!) {
		assert false
	}
	// {1: "a", "1": "b"} would give two "1" keys
	if _ := msgpack.decode_to_json(hex.decode('8201a161a131a162')!) {
		assert false
	}
	// a str that is not UTF-8, accepted by the decoder on request
	if _ := msgpack.decode_to_json(hex.decode('a2c328')!, validate_utf8: false) {
		assert false
	}
}

struct Doc {
	title string
	data  []u8
}

fn test_encode_to_json() {
	assert msgpack.encode_to_json(Doc{'a', [u8(1), 2, 3]})! == '{"title":"a","data":"AQID"}'
	if _ := msgpack.encode_to_json(math.inf(1)) {
		assert false
	}
}
