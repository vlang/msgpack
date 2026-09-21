// Compare MessagePack with V's current JSON codec.
// Run with: v -prod run examples/bench_msgpack_json_vs_json2.v

module main

import os
import json2
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
	b.measure('json2.decode\n')

	// encoding measurements:
	p := json2.decode[Person](s)!

	for _ in 0 .. max_iterations {
		es := json2.encode(p)
		if es[0] != `{` {
			println('json2.encode error: ${es}')
		}
	}
	b.measure('json2.encode\n')

	for _ in 0 .. max_iterations {
		es := msgpack.encode[Person](p)!
		if p.age != 99 {
			println('error: ${es}')
		}
	}
	b.measure('msgpack.encode\n')

	encoded := msgpack.encode[Person](p)!
	for _ in 0 .. max_iterations {
		d := msgpack.decode[Person](encoded)!
		if d.age != 99 {
			println('error: ${d.name}')
		}
	}
	b.measure('msgpack.decode')
}
