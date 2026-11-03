module main

import msgpack
import encoding.hex
import time

struct Struct {
	a string
	b int
}

fn test_decoding() {
	// Test decoding integers
	assert msgpack.decode[int](hex.decode('d200000000')!)! == 0
	assert msgpack.decode[int](hex.decode('d20000002a')!)! == 42
	assert msgpack.decode[int](hex.decode('d2ffffff85')!)! == -123

	// Test decoding strings
	assert msgpack.decode[string](hex.decode('a568656c6c6f')!)! == 'hello'
	assert msgpack.decode[string](hex.decode('a0')!)! == '' // Test empty string

	// Test decoding arrays
	assert msgpack.decode[[]int](hex.decode('93d200000001d200000002d200000003')!)! == [
		1,
		2,
		3,
	]

	// assert msgpack.decode[[]u8](msgpack.encode([u8(1),1,2])!)! == [u8(1),1,2]
	// asser msgpack.decode[[]int](msgpack.encode([1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2])!)! == [1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]
	assert msgpack.decode[[]u32](msgpack.encode([u32(1), 1, 2])!)! == [u32(1), 1, 2]
	// assert msgpack.decode[[]u8](msgpack.encode([u8(1),1,1])!)! == [u8(1), 2, 3]
	assert msgpack.decode[[]int](msgpack.encode([1, 1, 1])!)! == [1, 1, 1]
	assert msgpack.decode[[]int](hex.decode('90')!)! == []

	// // Test decoding maps
	// assert msgpack.decode[map[string]string](hex.decode('82a46e616d65a44a6f686ea3616765a23330')!)! == {
	// 	'name': 'John'
	// 	'age':  '30'
	// }
	// assert msgpack.decode[map[string]string](hex.decode('80')!)! == {} // Test empty map

	// Test decoding structs
	assert msgpack.decode[Struct](hex.decode('82a161a44a6f686ea162d20000001e')!)! == Struct{'John', 30}
	// Round-trip (works regardless of which integer width the encoder picks)
	assert msgpack.decode[Struct](msgpack.encode(Struct{'John', 30})!)! == Struct{'John', 30}
	assert msgpack.decode[Struct](msgpack.encode(Struct{'', 0})!)! == Struct{'', 0}

	// Test decoding booleans
	assert msgpack.decode[bool](hex.decode('c3')!)! == true
	assert msgpack.decode[bool](hex.decode('c2')!)! == false

	// Test decoding floating-point numbers
	assert msgpack.decode[f64](hex.decode('cb40091eb851eb851f')!)! == 3.14
	assert msgpack.decode[f32](hex.decode('ca4048f5c3')!)! == 3.14

	// Test decoding time
	assert msgpack.decode[time.Time](hex.decode('d6ff642196d0')!)! == time.unix(1679922896)

	// // Test decoding byte slices
	// assert msgpack.decode[[]u8](hex.decode('c403010203')!)! == [u8(1), 2, 3]
}

fn test_decode_floats_at_nonzero_offsets() ! {
	assert msgpack.decode[[]f32](hex.decode('92ca3fc00000cac0100000')!)! == [f32(1.5), -2.25]
	assert msgpack.decode[[]f64](hex.decode('92cb3ff8000000000000cbc002000000000000')!)! == [
		1.5,
		-2.25,
	]
}

fn test_decode_timestamp_formats_and_offsets() ! {
	assert msgpack.decode[time.Time](hex.decode('d7ff0000000400000001')!)! == time.unix_nanosecond(1, 1)
	assert msgpack.decode[time.Time](hex.decode('c70cff00000001ffffffffffffffff')!)! == time.unix_nanosecond(-1, 1)
	assert msgpack.decode[[]time.Time](hex.decode('92d7ff0000000400000001d6ff00000002')!)! == [
		time.unix_nanosecond(1, 1),
		time.unix(2),
	]
}

fn test_decode_truncated_float_and_timestamp() ! {
	for data in ['ca000000', 'cb00000000000000'] {
		if _ := msgpack.decode[f64](hex.decode(data)!) {
			assert false
		}
	}
	for data in ['d6ff000000', 'd7ff00000000000000', 'c70cff0000000000000000000000'] {
		if _ := msgpack.decode[time.Time](hex.decode(data)!) {
			assert false
		}
	}
}
