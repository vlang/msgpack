// Compares msgpack with the CBOR and JSON codecs of vlib, on the same data:
//   v -prod run examples/bench_msgpack_json_vs_json2.v
// Set MAX_ITERATIONS to change the number of iterations (default 100000).
module main

import benchmark
import encoding.cbor
import json2
import msgpack
import os

struct Person {
	name  string
	age   int
	email string
	score f64
	tags  []string
}

fn main() {
	n := os.getenv_opt('MAX_ITERATIONS') or { '100000' }.int()
	p := Person{'Bilbo Baggins', 111, 'bilbo@shire.me', 3.5, ['hobbit', 'burglar']}
	mp := msgpack.encode(p)!
	cb := cbor.encode(p, cbor.EncodeOpts{})!
	js := json2.encode(p)
	// every codec must give the value back before its speed means anything
	assert msgpack.decode[Person](mp)! == p
	assert cbor.decode[Person](cb, cbor.DecodeOpts{})! == p
	assert json2.decode[Person](js)! == p
	println('${n} iterations; encoded size: msgpack ${mp.len} B, cbor ${cb.len} B, json ${js.len} B')
	mut total := 0
	mut b := benchmark.start()

	for _ in 0 .. n {
		total += msgpack.encode(p)!.len
	}
	b.measure('msgpack.encode')
	for _ in 0 .. n {
		total += cbor.encode(p, cbor.EncodeOpts{})!.len
	}
	b.measure('cbor.encode')
	for _ in 0 .. n {
		total += json2.encode(p).len
	}
	b.measure('json2.encode\n')

	for _ in 0 .. n {
		total += msgpack.decode[Person](mp)!.age
	}
	b.measure('msgpack.decode')
	for _ in 0 .. n {
		total += cbor.decode[Person](cb, cbor.DecodeOpts{})!.age
	}
	b.measure('cbor.decode')
	for _ in 0 .. n {
		total += json2.decode[Person](js)!.age
	}
	b.measure('json2.decode\n')

	// A reused Packer encodes without allocating a new buffer each time.
	mut packer := msgpack.new_packer()
	for _ in 0 .. n {
		packer.reset()
		packer.pack(p)!
		total += packer.bytes().len
	}
	b.measure('msgpack Packer.pack, reused')
	assert total > 0
}
