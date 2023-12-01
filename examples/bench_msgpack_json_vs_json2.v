module main

import os
import json
import x.json2
import msgpack
import benchmark
// import time

struct Person {
	name string
	age  int
	// created_at time.Time
}

fn main() {
	max_iterations := os.getenv_opt('MAX_ITERATIONS') or { '1000000' }.int()
	// s := '{"name":"Bilbo Baggins","age":99,"created_at":1670840340}'
	s := '{"name":"Bilbo Baggins","age":99}'
	mut b := benchmark.start()

	for _ in 0 .. max_iterations {
		p := json2.decode[Person](s)!
		if p.age != 99 {
			println('error: ${p}')
		}
	}
	b.measure('json2.decode')

	for _ in 0 .. max_iterations {
		p := json.decode(Person, s)!
		if p.age != 99 {
			println('error: ${p}')
		}
	}
	b.measure('json.decode\n')

	// encoding measurements:
	p := json.decode(Person, s)!

	for _ in 0 .. max_iterations {
		es := json2.encode(p)
		if es[0] != `{` {
			println('json2.encode error: ${es}')
		}
	}
	b.measure('json2.encode')

	for _ in 0 .. max_iterations {
		es := json.encode(p)
		if es[0] != `{` {
			println('json.encode error: ${es}')
		}
	}
	b.measure('json.encode\n')

	for _ in 0 .. max_iterations {
		es := msgpack.encode_to_json[Person](p)
		if es[0] != `{` {
			println('error: ${es}')
		}
	}
	b.measure('msgpack.encode_to_json')

	for _ in 0 .. max_iterations {
		es := msgpack.encode[Person](p)
		if p.age != 99 {
			println('error: ${es}')
		}
	}
	b.measure('msgpack.encode\n')

	// Not working for now - waiting for #20027 be solved
	// encoded := msgpack.encode[Person](p)
	// for _ in 0 .. max_iterations {
	// 	msgpack.decode[Person](encoded)!
	// }
	// b.measure('msgpack.decode')
}
