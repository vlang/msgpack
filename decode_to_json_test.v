module main

import msgpack
import encoding.hex

fn test_decode_to_json_array_test() {
	src := msgpack.encode([1, 2])
	result := msgpack.decode_to_json[[]int](src) or { panic('error decoding to JSON ${err}') }
	assert result == '[1,2]'
}

fn test_decode_to_json_map() {
	src := msgpack.encode({
		'key1': 1
		'key2': 2
	})
	result := msgpack.decode_to_json[map[string]int](src) or {
		panic('error decoding to JSON: ${err}')
	}
	assert result == '{"key1":1,"key2":2}'
}

fn test_to_json_array() {
	src := msgpack.encode([1, 2])
	mut d := msgpack.new_decoder(src)
	result := d.decode_to_json[[]u64](src) or { panic('error converting to JSON: ${err}') }
	assert result == '[1,2]'
}

fn test_to_json_map() {
	src := msgpack.encode({
		'key1': 1
		'key2': 2
	})
	mut d := msgpack.new_decoder(src)
	result := d.decode_to_json[map[string]int](src) or { panic('error converting to JSON') }
	assert result == '{"key1":1,"key2":2}'
}
