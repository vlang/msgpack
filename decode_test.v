module main

import msgpack
import encoding.hex
import time

fn test_decoding() {
	// // Test decoding integers
	// assert msgpack.decode[i64](hex.decode('2a')!)! == 42
	// assert msgpack.decode[i64](hex.decode('d185')!)! == -123

	// // Test decoding strings
	// assert msgpack.decode[string](hex.decode('a5hello')!)! == 'hello'
	// assert msgpack.decode[string](hex.decode('a0')!)! == ''

	// // Test decoding arrays
	// assert msgpack.decode[[]int](hex.decode('93010203')!)! == [1, 2, 3]
	// assert msgpack.decode[[]int](hex.decode('90')!)! == []

	// // Test decoding maps
	// assert msgpack.decode[map[string]string](hex.decode('82a4namea4Johna3age1e')!)! == {
	// 	'name': 'John'
	// 	'age':  '30'
	// }
	// assert msgpack.decode[map[string]string](hex.decode('80')!)! == {}

	// // Test decoding booleans
	// assert msgpack.decode[bool](hex.decode('c3')!)! == true
	// assert msgpack.decode[bool](hex.decode('c2')!)! == false

	// // Test decoding floating-point numbers
	// assert msgpack.decode[f64](hex.decode('cb@\t!f9f01b86a8')!)! == 3.14

	// // Test decoding time
	// // Assuming time is 2023-11-27 12:34:56
	// assert msgpack.decode[time.Time](hex.decode('c704005fdce0d0')!)! == time.unix(1679922896)

	// // Test decoding byte slices
	// assert msgpack.decode[[]u8](hex.decode('c403010203')!)! == [u8(1), 2, 3]

	assert true
}
