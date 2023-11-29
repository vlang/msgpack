module main

import msgpack
import time

pub struct TestStructA {
	field_a int         @[codec: 'codecdata1']
	field_b string      @[codec: 'codecdata2']
	field_c TestStructB
	field_d []string
	// TODO: fix compiler (comptime generic infer)
	// field_e map[string]int
	// field_f map[string]TestStructB
	field_g []TestStructB
	field_h time.Time
}

pub struct TestStructB {
	field_a int    @[codec: 'codecdata1']
	field_b string @[codec: 'codecdata2']
}

fn main() {
	ts := TestStructA{
		field_a: 111
		field_b: 'TestStructA.field_b'
		field_c: TestStructB{
			field_a: 222
			field_b: 'TestStructB.field_b'
		}
		field_d: ['apple', 'banana', 'coconut', 'durian']
		// field_e: {
		// 	'one':   1
		// 	'two':   2
		// 	'three': 3
		// 	'four':  4
		// }
		// field_f: {
		// 	'a': TestStructB{
		// 		field_a: 1
		// 		field_b: 'field_f.a.TestStructB.field_b'
		// 	},
		// 	'b': TestStructB{
		// 		field_a: 2
		// 		field_b: 'field_f.b.TestStructB.field_b'
		// 	}
		// }
		field_g: [
			TestStructB{
				field_a: 1
				field_b: 'field_g.b.TestStructB.field_b'
			},
			TestStructB{
				field_a: 2
				field_b: 'field_g.b.TestStructB.field_b'
			},
		]
		field_h: time.now()
	}

	// encode data
	// mut encoder := msgpack.new_encoder()
	// encoded := encoder.encode<TestStructA>(ts)
	encoded := msgpack.encode[TestStructA](ts)
	println('ts encoded:')
	println(encoded.hex())

	// encoded := msgpack.encode<int>(111)
	// encoded := msgpack.encode('msgpack vlang')
	// encoded := msgpack.encode({'a': 1, 'b': 2, 'c': 3, 'd': 4})
	// encoded := msgpack.encode(['apple', 'banana'])

	// decode bytes
	println('ts decoded:')
	mut decoder := msgpack.new_decoder()

	mut val := TestStructA{}
	decoder.decode[TestStructA](encoded, mut val) or { error('error decoding: ${err}') }

	result := msgpack.decode[TestStructA](encoded) or {
		eprintln('error decoding: ${err}')
		return
	}

	// decode string
	// decoder.decode(encoder.b)
	// decoder.decode_from_string('81ab546573745374727563744184a76669656c645f61d20000006fa76669656c645f62b354657374537472756374412e6669656c645f62a76669656c645f6381ab546573745374727563744282a76669656c645f61d2000000dea76669656c645f62b354657374537472756374422e6669656c645f62a76669656c645f64d6ff631396ef') or {
	// 	panic('error decoding: $err')
	// }
}
