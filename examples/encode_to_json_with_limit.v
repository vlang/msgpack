module main

import os
import json
import x.json2
import msgpack
import benchmark

struct Person {
	name string
	age  int
}

fn main() {
	p := Person{
		name: 'Bilbo Baggins'
		age: 99
	}

	mut fixed_string_buf := [29]u8{}
	msgpack.encode_to_json_using_fixed_buffer(p, mut fixed_string_buf)

	max_iterations := os.getenv_opt('MAX_ITERATIONS') or { '1000000' }.int()

	mut b := benchmark.start()
	for _ in 0 .. max_iterations {
		es := msgpack.encode_to_json_using_fixed_buffer(p, mut fixed_buf)
		if es[0] != `{` {
			println('error: ${es[0]}')
		}
	}

	b.measure('msgpack.encode_to_json')
}
