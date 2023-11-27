module main

import msgpack
import encoding.hex
import time

struct Struct {
	a string
	b int
}

fn test_encoding() {
	// Test encoding integers
	assert msgpack.encode(0) == hex.decode('d200000000')!
	assert msgpack.encode(42) == hex.decode('d20000002a')!
	assert msgpack.encode(-123) == hex.decode('d2ffffff85')!

	// Test encoding strings
	assert msgpack.encode('hello') == hex.decode('a568656c6c6f')!
	assert msgpack.encode('') == hex.decode('a0')!

	// Test encoding arrays
	// assert msgpack.encode([]) == hex.decode('90')!
	assert msgpack.encode([0]) == hex.decode('91d200000000')!
	assert msgpack.encode([0.0]) == hex.decode('91cb0000000000000000')!
	assert msgpack.encode(['']) == hex.decode('91a0')!
	assert msgpack.encode([1, 2, 3]) == hex.decode('93d200000001d200000002d200000003')! // REVIEW

	// Test encoding maps
	assert msgpack.encode({
		'name': 'John'
		'age':  '30'
	}) == hex.decode('82a46e616d65a44a6f686ea3616765a23330')!
	assert msgpack.encode(Struct{'John', 30}) == hex.decode('82a161a44a6f686ea162d20000001e')!
	// assert msgpack.encode({}) == hex.decode('80')!

	// Test encoding booleans
	assert msgpack.encode(true) == hex.decode('c3')!
	assert msgpack.encode(false) == hex.decode('c2')!

	// Test encoding floating-point numbers
	assert msgpack.encode(3.14) == hex.decode('cb40091eb851eb851f')!

	// Test encoding time
	// Assuming time is 2023-11-27 12:34:56
	assert msgpack.encode(time.unix(1679922896)) == hex.decode('d6ff642196d0')! // REVIEW

	// Test encoding byte slices
	assert msgpack.encode([u8(1), 2, 3]) == hex.decode('c403010203')!
}
