module msgpack

// Marshaler lets a type choose how it is written, for instance as an
// extension value. `to_msgpack` must write exactly one value, and be public.
//
//   pub fn (id Uuid) to_msgpack(mut p msgpack.Packer) ! {
//       p.pack_ext(1, id.bytes[..])!
//   }
pub interface Marshaler {
	to_msgpack(mut p Packer) !
}

// Unmarshaler lets a type choose how it is read. `from_msgpack` must read
// exactly one value, and be public.
//
//   pub fn (mut id Uuid) from_msgpack(mut u msgpack.Unpacker) ! {
//       ext := u.unpack_ext()!
//       ...
//   }
pub interface Unmarshaler {
mut:
	from_msgpack(mut u Unpacker) !
}

// RawMessage holds one encoded MessagePack value. It is written as is, and
// reading one captures the bytes of the next value without decoding them:
// use it to delay decoding, or to pass a value through unchanged.
pub struct RawMessage {
pub:
	data []u8
}

// pack_raw writes the encoded value held by `raw`. It fails unless `raw`
// holds exactly one structurally complete value (see `skip_value`).
pub fn (mut p Packer) pack_raw(raw RawMessage) ! {
	check_one_value(raw.data, 'RawMessage')!
	p.put_bytes(raw.data.data, raw.data.len)
}

// unpack_raw captures the bytes of the next value.
pub fn (mut u Unpacker) unpack_raw() !RawMessage {
	start := u.cur
	u.skip_value()!
	return RawMessage{
		data: u.data[start..u.cur].clone()
	}
}

// pack_marshaler calls `to_msgpack` and checks that it wrote one
// structurally complete value.
fn (mut p Packer) pack_marshaler[T](val T) ! {
	start := p.buf.len
	val.to_msgpack(mut p) or {
		unsafe {
			p.buf.len = start
		}
		return err
	}
	check_one_value(p.buf[start..], '${T.name}.to_msgpack') or {
		unsafe {
			p.buf.len = start
		}
		return err
	}
}

// read_unmarshaler calls `from_msgpack` and checks that it read one value.
fn (mut u Unpacker) read_unmarshaler[T]() !T {
	start := u.cur
	u.skip_value()!
	end := u.cur
	u.cur = start
	mut val := T{}
	val.from_msgpack(mut u)!
	if u.cur != end {
		return error('msgpack: ${T.name}.from_msgpack read ${u.cur - start} byte(s) instead of the ${end - start} of one value')
	}
	return val
}

fn check_one_value(data []u8, source string) ! {
	mut u := new_unpacker(data)
	u.skip_value() or { return error('msgpack: ${source} did not produce a complete value: ${err.msg()}') }
	if !u.done() {
		return error('msgpack: ${source} produced more than one value')
	}
}
