module main

import msgpack
import time

struct TestStructA {
	field_a int         [codec: 'codecdata1']
	field_b string      [codec: 'codecdata2']
	field_c TestStructB
	field_d time.Time
}

struct TestStructB {
	field_a int    [codec: 'codecdata1']
	field_b string [codec: 'codecdata2']
}

fn main() {
	mut encoder := msgpack.new_encoder()
	ts := TestStructA{
		field_a: 111
		field_b: 'TestStructA.field_b'
		field_c: TestStructB{
			field_a: 222
			field_b: 'TestStructB.field_b'
		}
		field_d: time.now()
	}
	_ = ts
	encoder.encode<TestStructA>(ts)
	// encoder.encode<int>(111)
	// encoder.encode('msgpack vlang')
	// encoder.encode({'a': 1, 'b': 2, 'c': 3, 'd': 4})
	// encoder.encode(['apple', 'bananna'])
	println(encoder)

	mut decoder := msgpack.new_decoder()
	// decoder.decode(encoder.b)
	decoder.decode_from_string('81ab546573745374727563744184a76669656c645f61d20000006fa76669656c645f62b354657374537472756374412e6669656c645f62a76669656c645f6381ab546573745374727563744282a76669656c645f61d2000000dea76669656c645f62b354657374537472756374422e6669656c645f62a76669656c645f64d6ff631396ef') or {
		panic('error decoding: $err')
	}
	// decoder.decode_string('92a56170706c65a762616e616e6e61')
}
