module msgpack

import strings
import math
import time

struct Encoder {
mut:
	b         strings.Builder = strings.new_builder(1000)
	config    Config = default_config()
}

pub fn new_encoder() Encoder {
	return Encoder{}
}

pub fn (e &Encoder) str() string {
	return e.b.hex()
}

pub fn (mut e Encoder) encode<T>(data T) {
	$if T.typ is string {
		e.encode_string(data)
	} $else $if T.typ is bool {
		e.encode_bool(data)
	} $else $if T.typ is i8 {
		e.encode_i8(data)
	} $else $if T.typ is i16 {
		e.encode_i16(data)
	} $else $if T.typ is int {
		e.encode_i32(data)
	} $else $if T.typ is i64 {
		e.encode_i64(data)
	} $else $if T.typ is u8 {
		e.encode_u8(data)
	} $else $if T.typ is u16 {
		e.encode_u16(data)
	} $else $if T.typ is u32 {
		e.encode_u32(data)
	} $else $if T.typ is u64 {
		e.encode_u64(data)
	} $else $if T.typ is f32 {
		e.encode_f32(data)
	} $else $if T.typ is f64 {
		e.encode_f64(data)
	} $else $if T.typ is time.Time {
		e.encode_time(data)
	}
	$else $if T is $Array {
		e.write_array_start(data.len)
		for value in data {
			e.encode(value)
		}
	}
	$else $if T is $Map {
		e.write_map_start(data.len)
		for key, value in data {
			e.encode(key)
			e.encode(value)
		}
	}
	$else $if T is $Struct {
		// TODO: is there currently a way to get T.fields.len? if not, add it.
		mut fields_len := 0
		$for _ in T.fields { fields_len++ }
		if fields_len > 0 {
			e.write_map_start(1)
			e.encode_string(T.name)
			e.write_map_start(fields_len)
		}
		$for field in T.fields {
			mut codec_attr := ''
			for attr in field.attrs {
				if attr.starts_with('codec:') {
					codec_attr = attr.all_after(':').trim_space()
					break
				}
			}
			_ = codec_attr
			e.encode_string(field.name)
			e.encode(data.$(field.name))
			// FIXME: current fix in compiler is messed up.
			// concrete_types are not set correctly (something strange)
			// e.encode('sss')
		}
	}
}

pub fn (mut e Encoder) encode_bool(b bool) {
	println('encode_bool: $b')
	if b {
		e.b.write_u8(mp_true)
	} else {
		e.b.write_u8(mp_false)
	}
}

fn (mut e Encoder) encode_int(i i64) {
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

fn (mut e Encoder) encode_uint(i u64) {
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
	println('encode_i64:')
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
	e.write_u8(mp_float)
	e.write_f32(f)
}

pub fn (mut e Encoder) encode_f64(f f64) {
	e.write_u8(mp_double)
	e.write_f64(f)
}

pub fn (mut e Encoder) encode_map(s string) {

}

pub fn (mut e Encoder) encode_nil() {
	e.write_u8(mp_nil)
}


pub fn (mut e Encoder) encode_string(s string) {
	// println('encode_string: $s')
	ct := match e.config.write_ext {
		true {
			match e.config.string_raw {
				true { msgpack_container_bin }
				else { msgpack_container_str }
			}
		}
		else { msgpack_container_raw_legacy }
	}
	e.write_container_len(ct, s.len)
	if s.len > 0 {
		e.write_string(s)
	}
}

pub fn (mut e Encoder) encode_string_bytes_raw(bs []byte) {
	// TODO ?
	// if bs == nil {
	// 	e.encode_nil()
	// 	return
	// }
	if e.config.write_ext {
		e.write_container_len(msgpack_container_bin, bs.len)
	} else {
		e.write_container_len(msgpack_container_raw_legacy, bs.len)
	}
	if bs.len > 0 {
		e.write(bs)
	}
}

pub fn (mut e Encoder) encode_time(t time.Time) {
	// if t.is_zero() {
	if t.second == 0 && t.microsecond == 0 {
		e.encode_nil()
		return
	}
	if e.config.write_ext {
		e.encode_ext_preamble(mp_time_ext_type, 4)
	} else {
		e.write_container_len(msgpack_container_raw_legacy, 4)
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
	// 	e.write_container_len(msgpack_container_raw_legacy, l)
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

fn (mut e Encoder) encode_raw_ext(re &RawExt) {
	e.encode_ext_preamble(u8(re.tag), re.data.len)
	e.write(re.data)
}

fn (mut e Encoder) encode_ext_preamble(xtag u8, l int) {
	if l == 1 {
		e.write_u8(mp_fix_ext_1, xtag)
	} else if l == 2 {
		e.write_u8(mp_fix_ext_2, xtag)
	} else if l == 4 {
		e.write_u8(mp_fix_ext_4, xtag)
	} else if l == 8 {
		e.write_u8(mp_fix_ext_8, xtag)
	} else if l == 16 {
		e.write_u8(mp_fix_ext_16, xtag)
	} else if l < 256 {
		e.write_u8(mp_ext_8, u8(l), xtag)
	} else if l < 65536 {
		e.write_u8(mp_ext_16)
		e.write_u16(u16(l))
		e.write_u8(xtag)
	} else {
		e.write_u8(mp_ext_32)
		e.write_u32(u32(l))
		e.write_u8(xtag)
	}
}

fn (mut e Encoder) write_container_len(ct MsgpackContainerType, l int) {
	if ct.fix_cutoff > 0 && l < int(ct.fix_cutoff) {
		e.write_u8(ct.b_fix_min | u8(l))
	} else if ct.b8 > 0 && l < 256 {
		e.write_u8(ct.b8, u8(l))
	} else if l < 65536 {
		e.write_u8(ct.b16)
		e.write_u16(u16(l))
	} else {
		e.write_u8(ct.b32)
		e.write_u32(u32(l))
	}
}

fn (mut e Encoder) write_array_start(length int) {
	e.write_container_len(msgpack_container_list, length)
}

fn (mut e Encoder) write_map_start(length int) {
	e.write_container_len(msgpack_container_map, length)
}

fn (mut e Encoder) write_string(s string) {
	e.b.write_string(s)
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

fn (mut e Encoder) write(b []u8) {
	e.b.write(b) or {
		panic('write error')
	}
}

fn (mut e Encoder) write_u8(b ...u8) {
	if b.len > 1 {
		e.write(b)
	} else {
		e.b.write_u8(b[0])
	}
}
