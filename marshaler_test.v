module main

import encoding.hex
import msgpack

// Uuid is written as extension type 1 with its 16 bytes.
struct Uuid {
mut:
	bytes []u8
}

pub fn (id Uuid) to_msgpack(mut p msgpack.Packer) ! {
	p.pack_ext(1, id.bytes)!
}

pub fn (mut id Uuid) from_msgpack(mut u msgpack.Unpacker) ! {
	ext := u.unpack_ext()!
	if ext.type_id != 1 || ext.data.len != 16 {
		return error('not a UUID')
	}
	id.bytes = ext.data
}

struct Order {
	id    Uuid
	extra msgpack.RawMessage
}

// Broken writes two values instead of one.
struct Broken {}

pub fn (b Broken) to_msgpack(mut p msgpack.Packer) ! {
	p.pack_nil()
	p.pack_nil()
}

// Greedy reads less than the value it is given.
struct Greedy {}

pub fn (mut g Greedy) from_msgpack(mut u msgpack.Unpacker) ! {
	u.unpack_array_header()!
}

fn test_marshaler_writes_an_extension() {
	id := Uuid{
		bytes: []u8{len: 16, init: u8(index)}
	}
	data := msgpack.encode(id)!
	assert data.hex() == 'd801' + id.bytes.hex()
	assert msgpack.decode[Uuid](data)!.bytes == id.bytes
}

fn test_marshaler_inside_a_struct() {
	o := Order{
		id:    Uuid{
			bytes: []u8{len: 16}
		}
		extra: msgpack.RawMessage{
			data: msgpack.encode([1, 2])!
		}
	}
	data := msgpack.encode(o)!
	back := msgpack.decode[Order](data)!
	assert back.id.bytes == o.id.bytes
	assert back.extra.data == hex.decode('920102')!
	assert msgpack.decode[[]int](back.extra.data)! == [1, 2]
}

fn test_invalid_marshaler_output_is_rejected() {
	if _ := msgpack.encode([Broken{}]) {
		assert false
	} else {
		assert err.msg().contains('more than one value')
	}
	if _ := msgpack.encode(msgpack.RawMessage{ data: [u8(0x92), 0x01] }) {
		assert false
	}
}

fn test_unmarshaler_must_read_one_value() {
	if _ := msgpack.decode[Greedy](hex.decode('920102')!) {
		assert false
	}
	if _ := msgpack.decode[Uuid](hex.decode('d40101')!) {
		assert false
	} else {
		assert err.msg() == 'not a UUID'
	}
}
