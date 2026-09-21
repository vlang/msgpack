module main

import msgpack
import time

pub struct TestStructA {
	field_a int    @[codec: 'codecdata1']
	field_b string @[codec: 'codecdata2']
	field_c TestStructB
	field_d []string
	field_e map[string]int
	field_f map[string]TestStructB
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
		field_e: {
			'one':   1
			'two':   2
			'three': 3
			'four':  4
		}
		field_f: {
			'a': TestStructB{
				field_a: 1
				field_b: 'field_f.a.TestStructB.field_b'
			}
			'b': TestStructB{
				field_a: 2
				field_b: 'field_f.b.TestStructB.field_b'
			}
		}
		field_g: [
			TestStructB{
				field_a: 1
				field_b: 'field_g.a.TestStructB.field_b'
			},
			TestStructB{
				field_a: 2
				field_b: 'field_g.b.TestStructB.field_b'
			},
		]
		field_h: time.now()
	}

	encoded := msgpack.encode(ts) or { panic(err) }
	println('ts encoded (${encoded.len} bytes):')
	println(encoded.hex())

	decoded := msgpack.decode[TestStructA](encoded) or { panic(err) }
	println('ts decoded:')
	println(decoded)

	println('as JSON:')
	println(msgpack.decode_to_json(encoded) or { panic(err) })
}
