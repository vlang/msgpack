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

	// assert msgpack.decode[[]u8](msgpack.encode([u8(1),1,2]))! == [u8(1),1,2]
	// asser msgpack.decode[[]int](msgpack.encode([1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]))! == [1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]
	assert msgpack.decode[[]u32](msgpack.encode([u32(1), 1, 2]))! == [u32(1), 1, 2]
	// assert msgpack.decode[[]u8](msgpack.encode([u8(1),1,1]))! == [u8(1), 2, 3]
	assert msgpack.decode[[]int](msgpack.encode([1, 1, 1]))! == [1, 1, 1]
	assert msgpack.decode[[]int](hex.decode('90')!)! == []

	// // Test decoding maps
	// assert msgpack.decode[map[string]string](hex.decode('82a46e616d65a44a6f686ea3616765a23330')!)! == {
	// 	'name': 'John'
	// 	'age':  '30'
	// }
	// assert msgpack.decode[map[string]string](hex.decode('80')!)! == {} // Test empty map

	// // Test decoding structs
	// assert msgpack.decode[Struct](hex.decode('82a161a44a6f686ea162d20000001e')!)! == Struct{'John', 30}

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
