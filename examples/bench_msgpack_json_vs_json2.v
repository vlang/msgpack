import os
import json
import x.json2
import msgpack
import time
import benchmark

struct Person {
	name       string
	age        int
	created_at time.Time
}

fn main() {
	max_iterations := os.getenv_opt('MAX_ITERATIONS') or { '1000' }.int()
	s := '{"name":"Bilbo Baggins","age":99,"created_at":1670840340}'
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
	b.measure('json.decode')

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
	b.measure('json.encode')

	for _ in 0 .. max_iterations {
		es := msgpack.encode[Person](p)
		if p.age != 99 {
			println('error: ${es}')
		}
	}
	b.measure('msgpack.encode')

	encoded := msgpack.encode[Person](p)

	mut decoder := msgpack.new_decoder()
	for _ in 0 .. max_iterations {
		m := decoder.decode(encoded)
		if m.age != 99 {
			println('error: ${m}')
		}
	}
	b.measure('msgpack.decode')
}
