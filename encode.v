module msgpack

import math
import time

pub struct Encoder {
pub mut:
	buffer []u8
	config Config = default_config()
}

pub fn new_encoder() Encoder {
	return Encoder{}
}

pub fn encode[T](data T) []u8 {
	mut encoder := new_encoder()
	return encoder.encode(data)
}

pub fn encode_to_json[T](data T) string {
	mut encoder := new_encoder()
	encoded := encoder.encode(data)
	return decode_to_json[T](encoded) or { '' }
}

pub fn encode_to_json_using_fixed_buffer[T, F](data T, mut fixed_buf F) string {
	mut encoder := new_encoder()
	encoded := encoder.encode(data)

	$if F is $array_fixed {
		return decode_to_json_using_fixed_buffer[T, F](encoded, mut fixed_buf) or { '' }
	} $else {
		eprintln('fixed_buf need be a fixed array')
		return ''
	}
}

pub fn (e &Encoder) str() string {
	return e.buffer.hex()
}

pub fn (e &Encoder) bytes() []u8 {
	return e.buffer
}

pub fn (mut e Encoder) encode[T](data T) []u8 {
	$if T is string {
		e.encode_string(data)
	} $else $if T is bool {
		e.encode_bool(data)
	}
	// TODO: if int encode_int, if uint encode_uint
	// instead of needing to check each type, also
	// then we will be using the smallest storage
	$else $if T is i8 {
		e.encode_i8(data)
	} $else $if T is i16 {
		e.encode_i16(data)
	} $else $if T is int {
		e.encode_i32(data)
	} $else $if T is i64 {
		e.encode_i64(data)
	} $else $if T is u8 {
		e.encode_u8(data)
	} $else $if T is u16 {
		e.encode_u16(data)
	} $else $if T is u32 {
		e.encode_u32(data)
	} $else $if T is u64 {
		e.encode_u64(data)
	} $else $if T is f32 {
		e.encode_f32(data)
	} $else $if T is f64 {
		e.encode_f64(data)
	} $else $if T is time.Time {
		e.encode_time(data)
	} $else $if T is []u8 {
		e.encode_string_bytes_raw(data)
	} $else $if T is $array {
		e.write_array_start(data.len)
		for value in data {
			e.encode(value)
		}
	} $else $if T is $map {
		e.write_map_start(data.len)
		for key, value in data {
			e.encode(key)
			e.encode(value)
		}
	} $else $if T is $struct {
		// TODO: is there currently a way to get T.fields.len? if not, add it.
		mut fields_len := 0
		$for _ in T.fields {
			fields_len++
		}
		// TODO: embedded fields
		if fields_len > 0 {
			// e.write_map_start(1)
			// e.encode_string(T.name)
			e.write_map_start(fields_len)
		}
		$for field in T.fields {
			value := data.$(field.name)
			mut codec_attr := ''
			for attr in field.attrs {
				if attr.starts_with('codec:') {
					codec_attr = attr.all_after('codec:').trim_space()
					break
				}
			}
			// TODO: omit empty arrays or fields
			if codec_attr.len > 0 {
				e.encode_string(codec_attr)
			} else {
				e.encode_string(field.name)
			}

			// e.encode(data.$(field.name)) // FIXME - not work - bug
			e.encode(value)
		}
	}
	return e.buffer
}

pub fn (mut e Encoder) encode_bool(b bool) {
	if b {
		e.buffer << mp_true
	} else {
		e.buffer << mp_false
	}
}

// encode using type just big enough to fit `i`
pub fn (mut e Encoder) encode_int(i i64) {
	if e.config.positive_int_unsigned && i >= 0 {
		e.encode_uint(u64(i))
	} else if i > math.max_i8 {
		if i <= math.max_i16 {
			e.encode_i16(i16(i))
		} else if i <= math.max_i32 {
			e.encode_i32(int(i))
		} else {
			e.encode_i64(i)
		}
	} else if i >= -32 {
		if e.config.no_fixed_num {
			e.encode_i8(i8(i))
		} else {
			e.write_u8(u8(i))
		}
	} else if i >= math.min_i8 {
		e.encode_i8(i8(i))
	} else if i >= math.min_i16 {
		e.encode_i16(i16(i))
	} else if i >= math.min_i32 {
		e.encode_i32(int(i))
	} else {
		e.encode_i64(i)
	}
}

// encode using type just big enough to fit `i`
pub fn (mut e Encoder) encode_uint(i u64) {
	if i <= math.max_i8 {
		if e.config.no_fixed_num {
			e.encode_u8(u8(i))
		} else {
			e.write_u8(u8(i))
		}
	} else if i <= math.max_u8 {
		e.encode_u8(u8(i))
	} else if i <= math.max_u16 {
		e.encode_u16(u16(i))
	} else if i <= math.max_u32 {
		e.encode_u32(u32(i))
	} else {
		e.encode_u64(u64(i))
	}
}

pub fn (mut e Encoder) encode_i8(i i8) {
	e.write_u8(mp_i8, u8(i))
}

pub fn (mut e Encoder) encode_i16(i i16) {
	e.write_u8(mp_i16)
	e.write_u16(u16(i))
}

pub fn (mut e Encoder) encode_i32(i int) {
	e.write_u8(mp_i32)
	e.write_u32(u32(i))
}

pub fn (mut e Encoder) encode_i64(i i64) {
	e.write_u8(mp_i64)
	e.write_u64(u64(i))
}

pub fn (mut e Encoder) encode_u8(i u8) {
	e.write_u8(mp_u8, u8(i))
}

pub fn (mut e Encoder) encode_u16(i u16) {
	e.write_u8(mp_u16)
	e.write_u16(i)
}

pub fn (mut e Encoder) encode_u32(i u32) {
	e.write_u8(mp_u32)
	e.write_u32(i)
}

pub fn (mut e Encoder) encode_u64(i u64) {
	e.write_u8(mp_u64)
	e.write_u64(i)
}

pub fn (mut e Encoder) encode_f32(f f32) {
	e.write_u8(mp_f32)
	e.write_f32(f)
}

pub fn (mut e Encoder) encode_f64(f f64) {
	e.write_u8(mp_f64)
	e.write_f64(f)
}

pub fn (mut e Encoder) encode_nil() {
	e.write_u8(mp_nil)
}

pub fn (mut e Encoder) encode_string(s string) {
	ct := match e.config.write_ext {
		true {
			match e.config.string_raw {
				true { container_bin }
				else { container_str }
			}
		}
		else {
			container_raw_legacy
		}
	}
	e.write_container_len(ct, s.len)
	if s.len > 0 {
		e.write_string(s)
	}
}

pub fn (mut e Encoder) encode_string_bytes_raw(bs []u8) {
	// TODO: check spec if we need nil for zero length array
	// if bs == nil {
	// 	e.encode_nil()
	// 	return
	// }
	if e.config.write_ext {
		e.write_container_len(container_bin, bs.len)
	} else {
		e.write_container_len(container_raw_legacy, bs.len)
	}
	if bs.len > 0 {
		e.write(bs)
	}
}

pub fn (mut e Encoder) encode_time(t time.Time) {
	// if t.is_zero() {
	if t.second == 0 && t.nanosecond == 0 {
		e.encode_nil()
		return
	}
	if e.config.write_ext {
		e.encode_ext_preamble(mp_time_ext_type, 4)
	} else {
		e.write_container_len(container_raw_legacy, 4)
	}
	e.write_u32(u32(t.unix))
	// NOTE: automatically use the best storage depending if we need nanosecond
	// precision or not. time.Time doesn't support nanosecond currently (I think)
	//
	// t = t.UTC()
	// sec, nsec := t.unix, uint64(t.nanoseconds)
	// var data64 uint64
	// var l = 4
	// if sec >= 0 && sec>>34 == 0 {
	// 	data64 = (nsec << 34) | uint64(sec)
	// 	if data64&0xffffffff00000000 != 0 {
	// 		l = 8
	// 	}
	// } else {
	// 	l = 12
	// }
	// if e.config.write_ext {
	// 	e.encode_ext_preamble(mp_time_ext_type, l)
	// } else {
	// 	e.write_container_len(container_raw_legacy, l)
	// }
	// switch l {
	// 	4:
	//	e.write_u32(u32(data64))
	// 	8:
	//	e.write_u64(data64))
	// 	12:
	//	e.write_u32(u32(nsec))
	//	e.write_u64(u64(sec))
	// }
}

// TODO: custom extension support
fn (mut e Encoder) encode_ext() {
	panic('not implemented')
}

fn (mut e Encoder) encode_raw_ext(re &RawExt) {
	e.encode_ext_preamble(u8(re.tag), re.data.len)
	e.write(re.data)
}

fn (mut e Encoder) encode_ext_preamble(tag u8, length int) {
	if length == 1 {
		e.write_u8(mp_fix_ext_1, tag)
	} else if length == 2 {
		e.write_u8(mp_fix_ext_2, tag)
	} else if length == 4 {
		e.write_u8(mp_fix_ext_4, tag)
	} else if length == 8 {
		e.write_u8(mp_fix_ext_8, tag)
	} else if length == 16 {
		e.write_u8(mp_fix_ext_16, tag)
	} else if length < 256 {
		e.write_u8(mp_ext_8, u8(length), tag)
	} else if length < 65536 {
		e.write_u8(mp_ext_16)
		e.write_u16(u16(length))
		e.write_u8(tag)
	} else {
		e.write_u8(mp_ext_32)
		e.write_u32(u32(length))
		e.write_u8(tag)
	}
}

fn (mut e Encoder) write_container_len(ct ContainerType, length int) {
	if ct.fix_cutoff > 0 && length < int(ct.fix_cutoff) {
		e.write_u8(ct.b_fix_min | u8(length))
	} else if ct.b8 > 0 && length < 256 {
		e.write_u8(ct.b8, u8(length))
	} else if length < 65536 {
		e.write_u8(ct.b16)
		e.write_u16(u16(length))
	} else {
		e.write_u8(ct.b32)
		e.write_u32(u32(length))
	}
}

pub fn (mut e Encoder) write_array_start(length int) {
	e.write_container_len(container_array, length)
}

pub fn (mut e Encoder) write_map_start(length int) {
	e.write_container_len(container_map, length)
}

fn (mut e Encoder) write_string(s string) {
	if s.len > 0 {
		unsafe { e.buffer.push_many(s.str, s.len) }
	}
}

fn (mut e Encoder) write_u16(i u16) {
	e.write(put_u16(i))
}

fn (mut e Encoder) write_u32(i u32) {
	e.write(put_u32(i))
}

fn (mut e Encoder) write_u64(i u64) {
	e.write(put_u64(i))
}

pub fn (mut e Encoder) write_f32(f f32) {
	e.write(put_u32(math.f32_bits(f)))
}

pub fn (mut e Encoder) write_f64(f f64) {
	e.write(put_u64(math.f64_bits(f)))
}

// write byte array
fn (mut e Encoder) write(b []u8) {
	unsafe { e.buffer.push_many(b.bytestr().str, b.bytestr().len) }
}

// write one or more bytes
fn (mut e Encoder) write_u8(b ...u8) {
	if b.len > 1 {
		e.buffer << b
	} else {
		e.buffer << b[0]
	}
}
