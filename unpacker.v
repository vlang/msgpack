module msgpack

import math
import time

// DecodeOpts tunes the decoder. The defaults are strict and safe for
// untrusted input.
@[params]
pub struct DecodeOpts {
pub:
	// max_depth bounds the nesting of arrays and maps.
	max_depth int = 256
	// validate_utf8 rejects str values that are not valid UTF-8.
	validate_utf8 bool = true
	// deny_unknown_fields makes struct decoding fail on keys that match no
	// field. By default they are skipped.
	deny_unknown_fields bool
	// deny_duplicate_keys makes map and struct decoding fail when a key
	// appears twice. By default the last value wins.
	deny_duplicate_keys bool
	// allow_trailing_bytes lets `decode` ignore bytes left after the first
	// value. By default they are an error.
	allow_trailing_bytes bool
	// max_buffer_size bounds the bytes a StreamDecoder buffers to complete one
	// value, so that a declared length cannot exhaust memory.
	max_buffer_size int = 100 * 1024 * 1024
}

// Kind classifies the next value without consuming it.
pub enum Kind {
	nil_val
	bool_val
	int_val  // negative fixint and int 8/16/32/64
	uint_val // positive fixint and uint 8/16/32/64
	f32_val
	f64_val
	str_val
	bin_val
	array_val
	map_val
	ext_val
}

// Unpacker reads MessagePack values one at a time from a byte buffer.
// Every read checks the remaining input first: malformed or truncated data
// returns an error, it never panics. After a type mismatch the position is
// left unchanged, so the caller can peek and retry with another type.
pub struct Unpacker {
pub:
	data []u8
	opts DecodeOpts
mut:
	cur     int // offset of the next value in `data`
	depth   int
	pending i64 // values left to walk through in skip_pending
}

// new_unpacker returns an Unpacker reading `data` from the start. A
// `max_depth` of 0 or less selects the default of 256.
pub fn new_unpacker(data []u8, opts DecodeOpts) Unpacker {
	return Unpacker{
		data: data
		opts: if opts.max_depth > 0 {
			opts
		} else {
			DecodeOpts{
				...opts
				max_depth: 256
			}
		}
	}
}

// pos returns the offset of the next value in `data`.
@[inline]
pub fn (u &Unpacker) pos() int {
	return u.cur
}

// done reports whether all input has been consumed.
@[inline]
pub fn (u &Unpacker) done() bool {
	return u.cur >= u.data.len
}

// remaining returns the number of unread bytes.
@[inline]
pub fn (u &Unpacker) remaining() int {
	return u.data.len - u.cur
}

// peek_kind returns the kind of the next value without consuming it.
@[direct_array_access]
pub fn (u &Unpacker) peek_kind() !Kind {
	if u.cur >= u.data.len {
		return eof_error(u.cur, 1, 0)
	}
	b := u.data[u.cur]
	if b == 0xc1 {
		return malformed(u.cur, 'never used format byte 0xc1')
	}
	return match b {
		0x00...0x7f, 0xcc...0xcf { .uint_val }
		0xe0...0xff, 0xd0...0xd3 { .int_val }
		0x80...0x8f, 0xde, 0xdf { .map_val }
		0x90...0x9f, 0xdc, 0xdd { .array_val }
		0xa0...0xbf, 0xd9...0xdb { .str_val }
		0xc0 { .nil_val }
		0xc2, 0xc3 { .bool_val }
		0xc4...0xc6 { .bin_val }
		0xc7...0xc9, 0xd4...0xd8 { .ext_val }
		0xca { .f32_val }
		else { .f64_val }
	}
}

// try_unpack_nil consumes the next value and returns true if it is nil.
// Otherwise nothing is consumed and it returns false.
@[direct_array_access; inline]
pub fn (mut u Unpacker) try_unpack_nil() bool {
	if u.cur < u.data.len && u.data[u.cur] == 0xc0 {
		u.cur++
		return true
	}
	return false
}

// unpack_nil consumes a nil value.
pub fn (mut u Unpacker) unpack_nil() ! {
	b := u.peek_byte()!
	if b != 0xc0 {
		return type_mismatch(u.cur, 'nil', b)
	}
	u.cur++
}

// unpack_bool reads a boolean.
pub fn (mut u Unpacker) unpack_bool() !bool {
	b := u.peek_byte()!
	if b == 0xc2 || b == 0xc3 {
		u.cur++
		return b == 0xc3
	}
	return type_mismatch(u.cur, 'bool', b)
}

// unpack_int reads an integer of any width and signedness that fits in i64.
pub fn (mut u Unpacker) unpack_int() !i64 {
	start := u.cur
	bits, negative := u.read_integer()!
	if !negative && bits > u64(max_i64) {
		u.cur = start
		return int_range(start, 'i64', bits.str())
	}
	return i64(bits)
}

// unpack_uint reads a non-negative integer of any width.
pub fn (mut u Unpacker) unpack_uint() !u64 {
	start := u.cur
	bits, negative := u.read_integer()!
	if negative {
		u.cur = start
		return int_range(start, 'u64', i64(bits).str())
	}
	return bits
}

// unpack_f64 reads a float64 or a float32. An integer is accepted when a
// float64 represents it exactly.
@[direct_array_access]
pub fn (mut u Unpacker) unpack_f64() !f64 {
	start := u.cur
	b := u.peek_byte()!
	match b {
		0xcb {
			u.need(9)!
			v := math.f64_from_bits(u.be64(u.cur + 1))
			u.cur += 9
			return v
		}
		0xca {
			u.need(5)!
			v := math.f32_from_bits(u.be32(u.cur + 1))
			u.cur += 5
			return f64(v)
		}
		else {
			bits, negative := u.read_float_integer(start, 'float')!
			f := if negative { f64(i64(bits)) } else { f64(bits) }
			if !int_is_exact(bits, negative, f) {
				u.cur = start
				return int_range(start, 'f64', int_text(bits, negative))
			}
			return f
		}
	}
}

// unpack_f32 reads a float32. A float64 is accepted and rounded to the
// nearest float32, as most implementations write every float as float64;
// beyond the range of f32 it becomes infinite. An integer is accepted when a
// float32 represents it exactly.
@[direct_array_access]
pub fn (mut u Unpacker) unpack_f32() !f32 {
	start := u.cur
	b := u.peek_byte()!
	match b {
		0xca {
			u.need(5)!
			v := math.f32_from_bits(u.be32(u.cur + 1))
			u.cur += 5
			return v
		}
		0xcb {
			u.need(9)!
			v := math.f64_from_bits(u.be64(u.cur + 1))
			u.cur += 9
			return f32(v)
		}
		else {
			bits, negative := u.read_float_integer(start, 'float')!
			f := if negative { f32(i64(bits)) } else { f32(bits) }
			if !int_is_exact(bits, negative, f64(f)) {
				u.cur = start
				return int_range(start, 'f32', int_text(bits, negative))
			}
			return f
		}
	}
}

// unpack_str reads a str value into a new string.
pub fn (mut u Unpacker) unpack_str() !string {
	ptr, len := u.read_str_view()!
	if len == 0 {
		return ''
	}
	return unsafe { tos(ptr, len) }.clone()
}

// unpack_bin reads a bin value into a new byte array.
pub fn (mut u Unpacker) unpack_bin() ![]u8 {
	start := u.cur
	b := u.peek_byte()!
	len := match b {
		0xc4 { u.read_len8()! }
		0xc5 { u.read_len16()! }
		0xc6 { u.read_len32()! }
		else { return type_mismatch(start, 'bin', b) }
	}
	u.check_payload(start, len)!
	out := u.data[u.cur..u.cur + len].clone()
	u.cur += len
	return out
}

// unpack_array_header reads an array header and returns its element count.
// The caller must then read exactly that many values.
pub fn (mut u Unpacker) unpack_array_header() !int {
	start := u.cur
	b := u.peek_byte()!
	n := match b {
		0x90...0x9f {
			u.cur++
			int(b & 0x0f)
		}
		0xdc {
			u.read_len16()!
		}
		0xdd {
			u.read_len32()!
		}
		else {
			return type_mismatch(start, 'array', b)
		}
	}
	// Every element takes at least one byte: reject counts the input
	// cannot hold before a caller allocates for them.
	if n > u.data.len - u.cur {
		err := eof_error(u.cur, n, u.data.len - u.cur)
		u.cur = start
		return err
	}
	return n
}

// unpack_map_header reads a map header and returns its number of key/value
// pairs. The caller must then read exactly twice that many values.
pub fn (mut u Unpacker) unpack_map_header() !int {
	start := u.cur
	b := u.peek_byte()!
	n := match b {
		0x80...0x8f {
			u.cur++
			int(b & 0x0f)
		}
		0xde {
			u.read_len16()!
		}
		0xdf {
			u.read_len32()!
		}
		else {
			return type_mismatch(start, 'map', b)
		}
	}
	if i64(n) * 2 > i64(u.data.len - u.cur) {
		err := eof_error(u.cur, i64(n) * 2, u.data.len - u.cur)
		u.cur = start
		return err
	}
	return n
}

// unpack_ext reads an extension value, including timestamps.
pub fn (mut u Unpacker) unpack_ext() !Ext {
	type_id, len := u.read_ext_header()!
	out := Ext{
		type_id: type_id
		data:    u.data[u.cur..u.cur + len].clone()
	}
	u.cur += len
	return out
}

// unpack_timestamp reads a timestamp extension in any of its three formats.
@[direct_array_access]
pub fn (mut u Unpacker) unpack_timestamp() !Timestamp {
	start := u.cur
	type_id, len := u.read_ext_header()!
	if type_id != timestamp_ext_type {
		u.cur = start
		return TypeMismatchError{
			pos:      start
			expected: 'timestamp'
			got:      'ext type ${type_id}'
		}
	}
	p := u.cur
	ts := match len {
		4 {
			Timestamp{
				seconds: i64(u.be32(p))
			}
		}
		8 {
			data64 := u.be64(p)
			Timestamp{
				seconds:     i64(data64 & 0x3_ffff_ffff)
				nanoseconds: u32(data64 >> 34)
			}
		}
		12 {
			Timestamp{
				seconds:     i64(u.be64(p + 4))
				nanoseconds: u.be32(p)
			}
		}
		else {
			u.cur = start
			return malformed(start, 'timestamp payload must be 4, 8 or 12 bytes, got ${len}')
		}
	}
	if ts.nanoseconds > 999_999_999 {
		u.cur = start
		return malformed(start, 'timestamp nanoseconds ${ts.nanoseconds} exceed 999999999')
	}
	u.cur += len
	return ts
}

// unpack_time reads a timestamp extension as a UTC `time.Time`.
pub fn (mut u Unpacker) unpack_time() !time.Time {
	start := u.cur
	ts := u.unpack_timestamp()!
	return ts.to_time() or {
		u.cur = start
		return malformed(start, err.msg())
	}
}

// skip_value consumes the next value, including everything nested in it,
// without allocating. It checks the structure only: str values are not
// validated as UTF-8, and nesting is not limited by `opts.max_depth` (the
// walk is iterative, so deep nesting cannot overflow the stack).
@[direct_array_access]
pub fn (mut u Unpacker) skip_value() ! {
	start := u.cur
	u.pending = 1
	u.skip_pending() or {
		u.cur = start
		return err
	}
}

// skip_pending consumes values until `u.pending` of them have been read. On
// error, `u.pending` still counts the value that could not be read and the
// position is at its start, so that a stream decoder can resume the walk once
// more input has arrived.
@[direct_array_access]
fn (mut u Unpacker) skip_pending() ! {
	for u.pending > 0 {
		u.pending--
		b := u.peek_byte() or {
			u.pending++
			return err
		}
		size := match b {
			0x00...0x7f, 0xe0...0xff, 0xc0, 0xc2, 0xc3 {
				i64(1)
			}
			0x80...0x8f {
				u.pending += i64(b & 0x0f) * 2
				1
			}
			0x90...0x9f {
				u.pending += i64(b & 0x0f)
				1
			}
			0xa0...0xbf {
				1 + i64(b & 0x1f)
			}
			0xcc, 0xd0 {
				2
			}
			0xcd, 0xd1 {
				3
			}
			0xca, 0xce, 0xd2 {
				5
			}
			0xcb, 0xcf, 0xd3 {
				9
			}
			0xd4 {
				3
			}
			0xd5 {
				4
			}
			0xd6 {
				6
			}
			0xd7 {
				10
			}
			0xd8 {
				18
			}
			0xc4, 0xd9 {
				u.need(2) or {
					u.pending++
					return err
				}
				2 + i64(u.data[u.cur + 1])
			}
			0xc5, 0xda {
				u.need(3) or {
					u.pending++
					return err
				}
				3 + i64(u.be16(u.cur + 1))
			}
			0xc6, 0xdb {
				u.need(5) or {
					u.pending++
					return err
				}
				5 + i64(u.be32(u.cur + 1))
			}
			0xc7 {
				u.need(2) or {
					u.pending++
					return err
				}
				3 + i64(u.data[u.cur + 1])
			}
			0xc8 {
				u.need(3) or {
					u.pending++
					return err
				}
				4 + i64(u.be16(u.cur + 1))
			}
			0xc9 {
				u.need(5) or {
					u.pending++
					return err
				}
				6 + i64(u.be32(u.cur + 1))
			}
			0xdc {
				u.need(3) or {
					u.pending++
					return err
				}
				u.pending += i64(u.be16(u.cur + 1))
				3
			}
			0xdd {
				u.need(5) or {
					u.pending++
					return err
				}
				u.pending += i64(u.be32(u.cur + 1))
				5
			}
			0xde {
				u.need(3) or {
					u.pending++
					return err
				}
				u.pending += i64(u.be16(u.cur + 1)) * 2
				3
			}
			0xdf {
				u.need(5) or {
					u.pending++
					return err
				}
				u.pending += i64(u.be32(u.cur + 1)) * 2
				5
			}
			else {
				u.pending++
				return malformed(u.cur, 'never used format byte 0xc1')
			}
		}
		if size > i64(u.data.len - u.cur) {
			u.pending++
			return eof_error(u.cur, size, u.data.len - u.cur)
		}
		u.cur += int(size)
		// Each u.pending value needs at least one byte.
		if u.pending > i64(u.data.len - u.cur) {
			return eof_error(u.cur, u.pending, u.data.len - u.cur)
		}
	}
}

// ---------------------------------------------------------------------------
// Internal readers
// ---------------------------------------------------------------------------

// read_float_integer reads an integer on behalf of a float reader, reporting
// any other type as a mismatch against `expected`.
fn (mut u Unpacker) read_float_integer(start int, expected string) !(u64, bool) {
	b := u.peek_byte()!
	if !(b <= 0x7f || b >= 0xe0 || (b >= 0xcc && b <= 0xd3)) {
		return type_mismatch(start, expected, b)
	}
	return u.read_integer()!
}

// int_is_exact reports whether the float `f` equals the integer given by
// `bits` and `negative` (see read_integer).
fn int_is_exact(bits u64, negative bool, f f64) bool {
	if negative {
		// every float in [-2^63, 0) converts back to i64 without overflow
		return f >= -9_223_372_036_854_775_808.0 && i64(f) == i64(bits)
	}
	return f < 18_446_744_073_709_551_616.0 && u64(f) == bits
}

fn int_text(bits u64, negative bool) string {
	return if negative { i64(bits).str() } else { bits.str() }
}

@[direct_array_access; inline]
fn (u &Unpacker) peek_byte() !u8 {
	if u.cur >= u.data.len {
		return eof_error(u.cur, 1, 0)
	}
	return u.data[u.cur]
}

// need checks that `n` bytes are available from the current position.
@[inline]
fn (u &Unpacker) need(n int) ! {
	if n > u.data.len - u.cur {
		return eof_error(u.cur, n, u.data.len - u.cur)
	}
}

// be16/be32/be64 read big-endian integers at `p`; callers check bounds.
@[direct_array_access; inline]
fn (u &Unpacker) be16(p int) u16 {
	return u16(u.data[p]) << 8 | u16(u.data[p + 1])
}

@[direct_array_access; inline]
fn (u &Unpacker) be32(p int) u32 {
	return u32(u.data[p]) << 24 | u32(u.data[p + 1]) << 16 | u32(u.data[p + 2]) << 8 | u32(u.data[p + 3])
}

@[direct_array_access; inline]
fn (u &Unpacker) be64(p int) u64 {
	return u64(u.be32(p)) << 32 | u64(u.be32(p + 4))
}

// read_integer reads any integer format. It returns the value's bits and
// whether the value is negative (in which case the bits are an i64).
@[direct_array_access]
fn (mut u Unpacker) read_integer() !(u64, bool) {
	start := u.cur
	b := u.peek_byte()!
	match b {
		0x00...0x7f {
			u.cur++
			return u64(b), false
		}
		0xe0...0xff {
			u.cur++
			return u64(i64(i8(b))), true
		}
		0xcc {
			u.need(2)!
			v := u.data[u.cur + 1]
			u.cur += 2
			return u64(v), false
		}
		0xcd {
			u.need(3)!
			v := u.be16(u.cur + 1)
			u.cur += 3
			return u64(v), false
		}
		0xce {
			u.need(5)!
			v := u.be32(u.cur + 1)
			u.cur += 5
			return u64(v), false
		}
		0xcf {
			u.need(9)!
			v := u.be64(u.cur + 1)
			u.cur += 9
			return v, false
		}
		0xd0 {
			u.need(2)!
			v := i64(i8(u.data[u.cur + 1]))
			u.cur += 2
			return u64(v), v < 0
		}
		0xd1 {
			u.need(3)!
			v := i64(i16(u.be16(u.cur + 1)))
			u.cur += 3
			return u64(v), v < 0
		}
		0xd2 {
			u.need(5)!
			v := i64(i32(u.be32(u.cur + 1)))
			u.cur += 5
			return u64(v), v < 0
		}
		0xd3 {
			u.need(9)!
			v := i64(u.be64(u.cur + 1))
			u.cur += 9
			return u64(v), v < 0
		}
		else {
			return type_mismatch(start, 'integer', b)
		}
	}
}

// read_len8/16/32 consume a format byte followed by a length field and
// return the length.
@[direct_array_access; inline]
fn (mut u Unpacker) read_len8() !int {
	u.need(2)!
	n := int(u.data[u.cur + 1])
	u.cur += 2
	return n
}

@[inline]
fn (mut u Unpacker) read_len16() !int {
	u.need(3)!
	n := int(u.be16(u.cur + 1))
	u.cur += 3
	return n
}

@[inline]
fn (mut u Unpacker) read_len32() !int {
	u.need(5)!
	n := i64(u.be32(u.cur + 1))
	// A length larger than the whole input can never be satisfied; failing
	// here also keeps the value within `int` on 32-bit targets.
	if n > i64(u.data.len) {
		return eof_error(u.cur, n, u.data.len - u.cur)
	}
	u.cur += 5
	return int(n)
}

// check_payload verifies that a `len`-byte payload follows the header. On
// failure it rewinds to `start`, the beginning of the value.
@[inline]
fn (mut u Unpacker) check_payload(start int, len int) ! {
	if len > u.data.len - u.cur {
		err := eof_error(u.cur, len, u.data.len - u.cur)
		u.cur = start
		return err
	}
}

// read_str_view consumes a str value and returns a pointer to its bytes
// inside the input buffer, without copying.
@[direct_array_access]
fn (mut u Unpacker) read_str_view() !(&u8, int) {
	start := u.cur
	b := u.peek_byte()!
	len := match b {
		0xa0...0xbf {
			u.cur++
			int(b & 0x1f)
		}
		0xd9 {
			u.read_len8()!
		}
		0xda {
			u.read_len16()!
		}
		0xdb {
			u.read_len32()!
		}
		else {
			return type_mismatch(start, 'str', b)
		}
	}
	u.check_payload(start, len)!
	if u.opts.validate_utf8 && !utf8_valid(u.data, u.cur, len) {
		u.cur = start
		return InvalidUtf8Error{
			pos: start
		}
	}
	ptr := unsafe { &u8(u.data.data) + u.cur }
	u.cur += len
	return ptr, len
}

// read_ext_header consumes an extension header and returns its type and
// payload length, after checking that the payload is available.
@[direct_array_access]
fn (mut u Unpacker) read_ext_header() !(i8, int) {
	start := u.cur
	b := u.peek_byte()!
	mut len := 0
	match b {
		0xd4 {
			len = 1
			u.cur++
		}
		0xd5 {
			len = 2
			u.cur++
		}
		0xd6 {
			len = 4
			u.cur++
		}
		0xd7 {
			len = 8
			u.cur++
		}
		0xd8 {
			len = 16
			u.cur++
		}
		0xc7 {
			len = u.read_len8()!
		}
		0xc8 {
			len = u.read_len16()!
		}
		0xc9 {
			len = u.read_len32()!
		}
		else {
			return type_mismatch(start, 'ext', b)
		}
	}
	if u.cur >= u.data.len {
		err := eof_error(u.cur, 1 + len, 0)
		u.cur = start
		return err
	}
	type_id := i8(u.data[u.cur])
	u.cur++
	u.check_payload(start, len)!
	return type_id, len
}

// format_name describes a format byte for error messages.
fn format_name(b u8) string {
	return match b {
		0x00...0x7f, 0xcc...0xcf { 'uint' }
		0xe0...0xff, 0xd0...0xd3 { 'int' }
		0x80...0x8f, 0xde, 0xdf { 'map' }
		0x90...0x9f, 0xdc, 0xdd { 'array' }
		0xa0...0xbf, 0xd9...0xdb { 'str' }
		0xc0 { 'nil' }
		0xc2, 0xc3 { 'bool' }
		0xc4...0xc6 { 'bin' }
		0xc7...0xc9, 0xd4...0xd8 { 'ext' }
		0xca { 'float32' }
		0xcb { 'float64' }
		else { 'never used byte 0xc1' }
	}
}

// utf8_valid checks that data[start..start + len] is valid UTF-8: no
// overlong forms, no surrogates, nothing above U+10FFFF. Pure ASCII runs
// are skipped 8 bytes at a time.
@[direct_array_access]
fn utf8_valid(data []u8, start int, len int) bool {
	mut i := start
	end := start + len
	for i < end {
		for i + 8 <= end {
			mut chunk := u64(0)
			unsafe { vmemcpy(&chunk, &data[i], 8) }
			if chunk & 0x8080808080808080 != 0 {
				break
			}
			i += 8
		}
		if i >= end {
			break
		}
		c := data[i]
		if c < 0x80 {
			i++
			continue
		}
		n := if c & 0xe0 == 0xc0 {
			2
		} else if c & 0xf0 == 0xe0 {
			3
		} else if c & 0xf8 == 0xf0 {
			4
		} else {
			return false
		}
		if i + n > end {
			return false
		}
		match n {
			2 {
				if c < 0xc2 {
					return false
				}
			}
			3 {
				b := data[i + 1]
				if (c == 0xe0 && b < 0xa0) || (c == 0xed && b > 0x9f) {
					return false
				}
			}
			else {
				b := data[i + 1]
				if c > 0xf4 || (c == 0xf0 && b < 0x90) || (c == 0xf4 && b > 0x8f) {
					return false
				}
			}
		}
		for k in 1 .. n {
			if data[i + k] & 0xc0 != 0x80 {
				return false
			}
		}
		i += n
	}
	return true
}
