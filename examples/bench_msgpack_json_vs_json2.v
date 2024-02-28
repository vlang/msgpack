/*
╰─ v doctor ─╯
V full version: V 0.4.4 ed5c2f3.d5370bd
OS: linux, Ubuntu 23.10
Processor: 16 cpus, 64bit, little endian, AMD Ryzen 7 5800H with Radeon Graphics

╰─ v -prod crun examples/bench_msgpack_json_vs_json2.v ─╯
 SPENT   748.000 ms in json2.decode
 SPENT   178.232 ms in json.decode

 SPENT   300.852 ms in json2.encode
 SPENT   433.072 ms in json.encode

 SPENT   557.618 ms in msgpack.encode_to_json
 SPENT   129.682 ms in msgpack.encode
*/

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
