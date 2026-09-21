module msgpack

import math
import time

// EncodeOpts tunes the encoder.
@[params]
pub struct EncodeOpts {
pub:
	// initial_cap is the buffer capacity reserved up front, in bytes.
	initial_cap int = 128
}

// Packer writes MessagePack values into a growable buffer. Integers,
// strings, binaries, arrays, maps and extensions use their most compact
// format, as the spec recommends. Floats keep the width of their V type.
pub struct Packer {
pub:
	opts EncodeOpts
pub mut:
	buf []u8
}

// new_packer returns an empty Packer.
pub fn new_packer(opts EncodeOpts) Packer {
	return Packer{
		opts: opts
		buf:  []u8{cap: if opts.initial_cap > 0 { opts.initial_cap } else { 128 }}
	}
}

// bytes returns the encoded bytes. The slice shares the Packer's buffer:
// clone it before reusing the Packer.
@[inline]
pub fn (p &Packer) bytes() []u8 {
	return p.buf
}

// reset empties the buffer but keeps its capacity, to encode the next
// message without allocating.
@[inline]
pub fn (mut p Packer) reset() {
	unsafe {
		p.buf.len = 0
	}
}

// reserve makes room for at least `n` more bytes.
@[inline]
pub fn (mut p Packer) reserve(n int) {
	p.buf.ensure_cap(p.buf.len + n)
}

// pack_nil writes nil.
@[inline]
pub fn (mut p Packer) pack_nil() {
	p.put1(0xc0)
}

// pack_bool writes a boolean.
@[inline]
pub fn (mut p Packer) pack_bool(b bool) {
	p.put1(if b { u8(0xc3) } else { u8(0xc2) })
}

// pack_int writes a signed integer in the smallest format that holds it.
// Non-negative values use the unsigned formats, like most implementations.
pub fn (mut p Packer) pack_int(v i64) {
	if v >= 0 {
		p.pack_uint(u64(v))
	} else if v >= -32 {
		p.put1(u8(v))
	} else if v >= min_i8 {
		p.put8(0xd0, u8(v))
	} else if v >= min_i16 {
		p.put16(0xd1, u16(v))
	} else if v >= min_i32 {
		p.put32(0xd2, u32(v))
	} else {
		p.put64(0xd3, u64(v))
	}
}

// pack_uint writes an unsigned integer in the smallest format that holds it.
pub fn (mut p Packer) pack_uint(v u64) {
	if v <= 0x7f {
		p.put1(u8(v))
	} else if v <= max_u8 {
		p.put8(0xcc, u8(v))
	} else if v <= max_u16 {
		p.put16(0xcd, u16(v))
	} else if v <= max_u32 {
		p.put32(0xce, u32(v))
	} else {
		p.put64(0xcf, v)
	}
}

// pack_f32 writes a float32.
@[inline]
pub fn (mut p Packer) pack_f32(v f32) {
	p.put32(0xca, math.f32_bits(v))
}

// pack_f64 writes a float64.
@[inline]
pub fn (mut p Packer) pack_f64(v f64) {
	p.put64(0xcb, math.f64_bits(v))
}

// pack_str writes a string as a str value. It fails if the string is longer
// than the 2^32-1 bytes MessagePack allows.
pub fn (mut p Packer) pack_str(str string) ! {
	// a string inside the buffer could move when the header is written
	s := if p.owns(str.str) { str.clone() } else { str }
	if s.len <= 31 {
		p.put_fixstr(s)
		return
	} else if s.len <= max_u8 {
		p.put8(0xd9, u8(s.len))
	} else if s.len <= max_u16 {
		p.put16(0xda, u16(s.len))
	} else if u64(s.len) <= max_u32 {
		p.put32(0xdb, u32(s.len))
	} else {
		return error('msgpack: str of ${s.len} bytes exceeds the 4 GiB limit')
	}
	p.put_bytes(s.str, s.len)
}

// put_fixstr writes a string of at most 31 bytes, header and bytes at once.
// The string must not be inside the buffer.
@[inline]
fn (mut p Packer) put_fixstr(s string) {
	unsafe {
		mut d := p.extend(1 + s.len)
		d[0] = 0xa0 | u8(s.len)
		vmemcpy(d + 1, s.str, s.len)
	}
}

// put_key writes a struct field name, which is never inside the buffer.
// Unlike pack_str it cannot fail: a field name is far below the 4 GiB limit.
@[inline]
fn (mut p Packer) put_key(s string) {
	if s.len <= 31 {
		p.put_fixstr(s)
		return
	}
	if s.len <= max_u8 {
		p.put8(0xd9, u8(s.len))
	} else if s.len <= max_u16 {
		p.put16(0xda, u16(s.len))
	} else {
		p.put32(0xdb, u32(s.len))
	}
	p.put_bytes(s.str, s.len)
}

// pack_bin writes a byte array as a bin value. It fails if the data is
// longer than the 2^32-1 bytes MessagePack allows.
pub fn (mut p Packer) pack_bin(bytes []u8) ! {
	// bytes inside the buffer could move when the header is written
	data := if p.owns(bytes.data) { bytes.clone() } else { bytes }
	if data.len <= max_u8 {
		p.put8(0xc4, u8(data.len))
	} else if data.len <= max_u16 {
		p.put16(0xc5, u16(data.len))
	} else if u64(data.len) <= max_u32 {
		p.put32(0xc6, u32(data.len))
	} else {
		return error('msgpack: bin of ${data.len} bytes exceeds the 4 GiB limit')
	}
	p.put_bytes(data.data, data.len)
}

// pack_array_header starts an array of `n` elements. Exactly `n` values
// must follow.
pub fn (mut p Packer) pack_array_header(n u32) {
	if n <= 15 {
		p.put1(0x90 | u8(n))
	} else if n <= max_u16 {
		p.put16(0xdc, u16(n))
	} else {
		p.put32(0xdd, n)
	}
}

// pack_map_header starts a map of `n` key/value pairs. Exactly `2 * n`
// values must follow, alternating keys and values.
pub fn (mut p Packer) pack_map_header(n u32) {
	if n <= 15 {
		p.put1(0x80 | u8(n))
	} else if n <= max_u16 {
		p.put16(0xde, u16(n))
	} else {
		p.put32(0xdf, n)
	}
}

// pack_ext writes an extension value. Payloads of 1, 2, 4, 8 and 16 bytes
// use the fixext formats.
pub fn (mut p Packer) pack_ext(type_id i8, payload []u8) ! {
	// a payload inside the buffer could move when the header is written
	data := if p.owns(payload.data) { payload.clone() } else { payload }
	match data.len {
		1 { p.put1(0xd4) }
		2 { p.put1(0xd5) }
		4 { p.put1(0xd6) }
		8 { p.put1(0xd7) }
		16 { p.put1(0xd8) }
		else {
			if data.len <= max_u8 {
				p.put8(0xc7, u8(data.len))
			} else if data.len <= max_u16 {
				p.put16(0xc8, u16(data.len))
			} else if u64(data.len) <= max_u32 {
				p.put32(0xc9, u32(data.len))
			} else {
				return error('msgpack: ext of ${data.len} bytes exceeds the 4 GiB limit')
			}
		}
	}
	p.put1(u8(type_id))
	p.put_bytes(data.data, data.len)
}

// pack_timestamp writes a timestamp extension in the smallest of its three
// formats: 32-bit seconds, 34-bit seconds with nanoseconds, or 64-bit
// signed seconds with nanoseconds. It fails if nanoseconds exceed 999999999.
pub fn (mut p Packer) pack_timestamp(ts Timestamp) ! {
	if ts.nanoseconds > 999_999_999 {
		return error('msgpack: timestamp nanoseconds ${ts.nanoseconds} exceed 999999999')
	}
	p.put_timestamp(ts)
}

// pack_time writes a `time.Time` as a timestamp extension, keeping its
// nanoseconds.
@[inline]
pub fn (mut p Packer) pack_time(t time.Time) ! {
	p.put_timestamp(Timestamp.from_time(t)!)
}

fn (mut p Packer) put_timestamp(ts Timestamp) {
	if ts.seconds >= 0 && ts.seconds >> 34 == 0 {
		data64 := u64(ts.nanoseconds) << 34 | u64(ts.seconds)
		if data64 & 0xffff_ffff_0000_0000 == 0 {
			p.put8(0xd6, 0xff)
			p.put_be32(u32(data64))
		} else {
			p.put8(0xd7, 0xff)
			p.put_be64(data64)
		}
	} else {
		p.put8(0xc7, 12)
		p.put1(0xff)
		p.put_be32(ts.nanoseconds)
		p.put_be64(u64(ts.seconds))
	}
}

// ---------------------------------------------------------------------------
// Internal writers: each reserves its whole size once, then stores the bytes
// directly, like the store helpers of msgpack-c.
// ---------------------------------------------------------------------------

// extend grows the buffer by `n` bytes and returns a pointer to them.
@[inline]
fn (mut p Packer) extend(n int) &u8 {
	len := p.buf.len
	if len + n > p.buf.cap {
		p.buf.ensure_cap(len + n)
	}
	unsafe {
		p.buf.len = len + n
		return &u8(p.buf.data) + len
	}
}

@[inline]
fn (mut p Packer) put1(b u8) {
	unsafe {
		mut d := p.extend(1)
		d[0] = b
	}
}

@[inline]
fn (mut p Packer) put8(tag u8, v u8) {
	unsafe {
		mut d := p.extend(2)
		d[0] = tag
		d[1] = v
	}
}

@[inline]
fn (mut p Packer) put16(tag u8, v u16) {
	unsafe {
		mut d := p.extend(3)
		d[0] = tag
		store16(d + 1, v)
	}
}

@[inline]
fn (mut p Packer) put32(tag u8, v u32) {
	unsafe {
		mut d := p.extend(5)
		d[0] = tag
		store32(d + 1, v)
	}
}

@[inline]
fn (mut p Packer) put64(tag u8, v u64) {
	unsafe {
		mut d := p.extend(9)
		d[0] = tag
		store32(d + 1, u32(v >> 32))
		store32(d + 5, u32(v))
	}
}

@[inline]
fn (mut p Packer) put_be32(v u32) {
	unsafe { store32(p.extend(4), v) }
}

@[inline]
fn (mut p Packer) put_be64(v u64) {
	unsafe {
		d := p.extend(8)
		store32(d, u32(v >> 32))
		store32(d + 4, u32(v))
	}
}

@[inline; unsafe]
fn store16(d &u8, v u16) {
	unsafe {
		d[0] = u8(v >> 8)
		d[1] = u8(v)
	}
}

@[inline; unsafe]
fn store32(d &u8, v u32) {
	unsafe {
		d[0] = u8(v >> 24)
		d[1] = u8(v >> 16)
		d[2] = u8(v >> 8)
		d[3] = u8(v)
	}
}

// check_count converts an array or map length to the u32 a header holds.
@[inline]
fn check_count(n int) !u32 {
	if u64(n) > max_u32 {
		return error('msgpack: ${n} elements exceed the limit of 4294967295')
	}
	return u32(n)
}

// put_bytes appends `n` bytes from `src`, which must not be inside the
// buffer: growing it would move them.
@[inline]
fn (mut p Packer) put_bytes(src voidptr, n int) {
	if n > 0 {
		unsafe { vmemcpy(p.extend(n), src, n) }
	}
}

// owns reports whether `ptr` points into the buffer.
@[inline]
fn (p &Packer) owns(ptr voidptr) bool {
	base := u64(p.buf.data)
	return u64(ptr) >= base && u64(ptr) < base + u64(p.buf.cap)
}
