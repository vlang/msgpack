module msgpack

import time
import encoding.hex
import encoding.binary
import math

const msg_bad_desc = 'unrecognized descriptor byte'

struct Decoder {
	config Config = default_config()
mut:
	pos        int
	buffer     []u8
	bd         u8 // actual buffer value
	char_count int
}

pub fn new_decoder(src []u8) Decoder {
	return Decoder{
		buffer: src
	}
}

pub fn decode_to_json[T](src []u8) !string {
	mut d := new_decoder(src)

	json := d.decode_to_json[T](src) or { return error('error decoding to JSON: ${err}') }

	return json
}

pub fn (mut d Decoder) decode_to_json[T](src []u8) !string {
	d.next()!

	mut result := []u8{}

	defer {
		unsafe { result.free() }
	}

	data := d.buffer

	match d.bd {
		mp_array_16, mp_array_32, mp_fix_array_min...mp_fix_array_max {
			array_len := d.read_array_len(data) or { return error('error reading array length') }

			mut d_for_array := new_decoder(src[1..])

			result << `[`

			for i in 0 .. array_len {
				if i > 0 {
					result << `,`
				}

				element_json := d_for_array.decode_to_json[T](src[1..]) or {
					return error('error converting array element to JSON ${err}')
				}

				unsafe { result.push_many(element_json.str, element_json.len) }
			}

			result << `]`
		}
		mp_map_16, mp_map_32, mp_fix_map_min...mp_fix_map_max {
			map_len := d.read_map_len(src) or { return error('error reading map length') }

			result << `{`

			for i in 0 .. map_len {
				if i > 0 {
					result << `,`
				}

				key := d.decode_to_json[string](src) or {
					return error('error converting map key to JSON: ${err}')
				}
				unsafe { result.push_many(key.str, key.len) }
				result << `:`

				value_json := d.decode_to_json[T](src) or {
					return error('error converting map value to JSON')
				}
				unsafe { result.push_many(value_json.str().str, value_json.str().len) }
			}

			result << `}`
		}
		mp_nil {
			unsafe { result.push_many('null'.str, 'null'.len) }
			// d.pos +=
		}
		mp_true, mp_false {
			mut bool_val := false
			d.decode_bool(mut bool_val) or { return error('error decoding boolean: ${err}') }
			unsafe { result.push_many(bool_val.str().str, bool_val.str().len) }
		}
		mp_f32, mp_f64 {
			mut float_val := 0.0
			d.decode_float(mut float_val) or { return error('error decoding float: ${err}') }
			unsafe { result.push_many(float_val.str().str, float_val.str().len) }
		}
		mp_u8, mp_u16, mp_u32, mp_u64, mp_i8, mp_i16, mp_i32, mp_i64 {
			mut int_val := 0
			d.decode_integer(mut int_val) or { return error('error decoding integer: ${err}') }
			unsafe { result.push_many(int_val.str().str, int_val.str().len) }
		}
		mp_str_8, mp_str_16, mp_str_32, mp_fix_str_min...mp_fix_str_max {
			mut str_val := ''
			d.decode_string(mut str_val) or { return error('error decoding string: ${err}') }
			// TODO remove (result << `\"`) like in decode_to_json_using_fixed_buffer
			result << `"`
			unsafe { result.push_many(str_val.str, str_val.len) }
			result << `\"`
		}
		mp_bin_8, mp_bin_16, mp_bin_32 {
			bin_len := d.read_bin_len(src) or { return error('error reading binary length') }
			for i in 0 .. bin_len {
				unsafe { result.push_many(src[d.pos + i].str().str, src[d.pos + i].str().len) }
			}

			d.pos += bin_len
		}
		mp_ext_8, mp_ext_16, mp_ext_32 {
			// ext_len := d.read_ext_len(src) or { return error('error reading extension length') }
			// ext_type := d.read_ext_type(src) or { return error('error reading extension type') }
			// match ext_type {
			//     else {
			//         return error('unsupported extension type')
			//     }
			// }
			// d.pos += ext_len
		}
		mp_fix_ext_1, mp_fix_ext_2, mp_fix_ext_4, mp_fix_ext_8, mp_fix_ext_16 {
			// ext_len := int(d.bd - mp_fix_ext_1)
			// ext_type := d.read_ext_type(src) or { return error('error reading extension type') }
			// match ext_type {
			//     else {
			//         return error('unsupported extension type')
			//     }
			// }
			// d.pos += ext_len
		}
		else {
			return error('unsupported descriptor byte for conversion to JSON')
		}
	}
	return result.bytestr()
}

pub fn decode_to_json_using_fixed_buffer[T, F](src []u8, mut fixed_buf F) !string {
	mut d := new_decoder(src)

	json := d.decode_to_json_using_fixed_buffer[T, F](src, mut fixed_buf) or {
		return error('error decoding to JSON: ${err}')
	}

	return json
}

pub fn (mut d Decoder) decode_to_json_using_fixed_buffer[T, F](src []u8, mut fixed_buf F) !string {
	d.next()!

	match d.bd {
		mp_array_16, mp_array_32, mp_fix_array_min...mp_fix_array_max {
			array_len := d.read_array_len(src) or { return error('error reading array length') }

			// mut d_for_array := new_decoder(src)

			fixed_buf[d.char_count] = `[`

			for i in 0 .. array_len {
				if i > 0 {
					fixed_buf[d.char_count] = `,`
				}
			}
			fixed_buf[d.char_count] = `]`
		}
		mp_u8, mp_u16, mp_u32, mp_u64, mp_i8, mp_i16, mp_i32, mp_i64 {
			mut int_val := 0
			d.decode_integer(mut int_val) or { return error('error decoding integer: ${err}') }
			for letter in int_val.str() {
				fixed_buf[d.char_count] = letter
				d.char_count++
			}
		}
		mp_str_8, mp_str_16, mp_str_32, mp_fix_str_min...mp_fix_str_max {
			data := d.buffer
			// REVIEW - why it is slow??
			str_len := d.read_str_len(data) or { return error('error reading string length') }

			for letter in data[d.pos..d.pos + str_len] {
				fixed_buf[d.char_count] = letter
				d.char_count++
			}
			d.pos += str_len
		}
		mp_map_16, mp_map_32, mp_fix_map_min...mp_fix_map_max {
			map_len := d.read_map_len(src) or { return error('error reading map length') }

			fixed_buf[d.char_count] = `{`

			d.char_count++

			for map_idx in 0 .. map_len {
				if map_idx > 0 {
					fixed_buf[d.char_count] = `,`
					d.char_count++
				}

				_ := d.decode_to_json_using_fixed_buffer[string, F](src, mut fixed_buf) or {
					return error('error converting map key to JSON: ${err}')
				}

				fixed_buf[d.char_count] = `:`
				d.char_count++

				mut is_string := false
				if d.buffer[d.pos] == mp_str_8 || d.buffer[d.pos] == mp_str_16
					|| d.buffer[d.pos] == mp_str_32
					|| (d.buffer[d.pos] >= mp_fix_str_min && d.buffer[d.pos] <= mp_fix_str_max) {
					is_string = true
					fixed_buf[d.char_count] = `"`
					d.char_count++
				}
				_ := d.decode_to_json_using_fixed_buffer[string, F](src, mut fixed_buf) or {
					return error('error converting map value to JSON')
				}

				if is_string {
					fixed_buf[d.char_count] = `"`
					d.char_count++
				}
			}

			fixed_buf[d.char_count] = `}`
			d.char_count++
		}
		mp_nil {
			for letter in 'null' {
				fixed_buf[d.char_count] = letter
				d.char_count++
			}
			// d.pos +=
		}
		mp_true {
			for letter in 'true' {
				fixed_buf[d.char_count] = letter
				d.char_count++
			}
			// d.pos +=
		}
		mp_false {
			for letter in 'false' {
				fixed_buf[d.char_count] = letter
				d.char_count++
			}
			// d.pos +=
		}
		mp_f32, mp_f64 {
			mut float_val := 0.0
			d.decode_float(mut float_val) or { return error('error decoding float: ${err}') }
			for letter in float_val.str() {
				fixed_buf[d.char_count] = letter
				d.char_count++
			}
		}
		mp_bin_8, mp_bin_16, mp_bin_32 {
			bin_len := d.read_bin_len(src) or { return error('error reading binary length') }
			for i := 0; i < bin_len; i++ {
				for letter in src[d.pos].str() {
					fixed_buf[d.char_count] = letter
					d.char_count++
				}

				d.pos++
			}
		}
		mp_ext_8, mp_ext_16, mp_ext_32 {
			// ext_len := d.read_ext_len(src) or { return error('error reading extension length') }
			// ext_type := d.read_ext_type(src) or { return error('error reading extension type') }
			// match ext_type {
			//     else {
			//         return error('unsupported extension type')
			//     }
			// }
			// d.pos += ext_len
		}
		mp_fix_ext_1, mp_fix_ext_2, mp_fix_ext_4, mp_fix_ext_8, mp_fix_ext_16 {
			// ext_len := int(d.bd - mp_fix_ext_1)
			// ext_type := d.read_ext_type(src) or { return error('error reading extension type') }
			// match ext_type {
			//     else {
			//         return error('unsupported extension type')
			//     }
			// }
			// d.pos += ext_len
		}
		else {
			return error('unsupported descriptor byte for conversion to JSON')
		}
	}

	mut result := []u8{len: d.char_count}
	for id, variable in fixed_buf {
		if id == d.char_count {
			break
		}
		result[id] = variable
	}
	return result.bytestr()
}

pub fn decode[T](src []u8) !T {
	mut val := T{}

	mut d := new_decoder(src)
	d.decode[T](src, mut val) or { return error('error decoding data: ${err}') }

	return val
}

pub fn (mut d Decoder) decode_from_string[T](data string) ! {
	d.decode[T](hex.decode(data) or { return error('error decoding hex string') })!
}

pub fn (mut d Decoder) decode[T](data []u8, mut val T) ! {
	d.next()!

	$if T is $int {
		d.decode_integer[T](mut val) or { return error('error decoding integer: ${err}') }
	} $else $if T is $float {
		d.decode_float[T](mut val) or { return error('error decoding float: ${err}') }
	} $else $if T is string {
		d.decode_string[T](mut val) or { return error('error decoding string: ${err}') }
	} $else $if T is []u8 {
		d.decode_binary[T](mut val) or { return error('error decoding binary: ${err}') }
	} $else $if T is $array {
		d.decode_array(mut val) or { return error('error decoding array: ${err}') }
	} $else $if T is $map {
		d.decode_map[T](mut val) or { return error('error decoding map: ${err}') }
	} $else $if T is time.Time {
		d.decode_time[T](mut val) or { return error('error decoding time: ${err}') }
	} $else $if T is $struct {
		d.decode_struct[T](mut val) or { return error('error decoding struct: ${err}') }
	} $else $if T is bool {
		d.decode_bool[T](mut val) or { return error('error decoding boolean: ${err}') }
	} $else {
		return error('unsupported type for decoding: ${T.name}')
	}
}

pub fn (mut d Decoder) decode_integer[T](mut val T) ! {
	data := d.buffer
	match d.bd {
		mp_u8 {
			val = data[d.pos]
			d.pos++
		}
		mp_u16 {
			val = u64(binary.big_endian_u16(data[d.pos..d.pos + 2]))
			d.pos += 2
		}
		mp_u32 {
			val = u64(int(binary.big_endian_u32(data[d.pos..d.pos + 4])))
			d.pos += 4
		}
		mp_u64 {
			val = u64(binary.big_endian_u64(data[d.pos..d.pos + 8]))
			d.pos += 8
		}
		mp_i8 {
			val = i64(data[d.pos])
			d.pos++
		}
		mp_i16 {
			val = i64(i16(binary.big_endian_u16(data[d.pos..d.pos + 2])))
			d.pos += 2
		}
		mp_i32 {
			val = i64(i32(binary.big_endian_u32(data[d.pos..d.pos + 4])))
			d.pos += 4
		}
		mp_i64 {
			val = i64(binary.big_endian_u64(data[d.pos..d.pos + 8]))
			d.pos += 8
		}
		else {
			return error('invalid integer descriptor byte')
		}
	}
}

pub fn (mut d Decoder) decode_float[T](mut val T) ! {
	data := d.buffer
	match d.bd {
		mp_f32 {
			val = math.f32_from_bits(binary.big_endian_u32(data[1..4]))
			d.pos += 4
		}
		mp_f64 {
			val = math.f64_from_bits(binary.big_endian_u64(data[1..8]))
			d.pos += 8
		}
		else {
			return error('invalid float descriptor byte')
		}
	}
}

pub fn (mut d Decoder) decode_string[T](mut val T) ! {
	data := d.buffer
	match d.bd {
		mp_str_8, mp_str_16, mp_str_32, mp_fix_str_min...mp_fix_str_max {
			str_len := d.read_str_len(data) or { return error('error reading string length') }
			val = data[d.pos..d.pos + str_len].bytestr()
			d.pos += str_len
		}
		else {
			return error('invalid string descriptor byte')
		}
	}
}

pub fn (mut d Decoder) decode_binary[T](mut val T) ! {
	data := d.buffer
	match d.bd {
		mp_bin_8, mp_bin_16, mp_bin_32 {
			bin_len := d.read_bin_len(data) or { return error('error reading binary length') }
			val = data[d.pos..d.pos + bin_len]
			d.pos += bin_len
		}
		else {
			return error('invalid binary descriptor byte')
		}
	}
}

pub fn (mut d Decoder) decode_array[T](mut val []T) ! {
	data := d.buffer
	match d.bd {
		mp_array_16, mp_array_32, mp_fix_array_min...mp_fix_array_max {
			array_len := d.read_array_len(data) or { return error('error reading array length') }
			elements_buffer := data[1..]

			mut d_for_array := new_decoder(elements_buffer)

			for _ in 0 .. array_len {
				mut element := T{}

				d_for_array.decode[T](elements_buffer, mut element) or {
					return error('error decoding array element')
				}

				val << element
			}
		}
		else {
			return error('invalid array descriptor byte')
		}
	}
}

// TODO
pub fn (mut d Decoder) decode_map[T](mut val T) ! {
	data := d.buffer
	match d.bd {
		mp_map_16, mp_map_32, mp_fix_map_min...mp_fix_map_max {
			map_len := d.read_map_len(data) or { return error('error reading map length') }
			for _ in 0 .. map_len {
				mut key := ''

				key = decode[string](data[d.pos..]) or { return error('error decoding map key') }

				d.pos += key.len + 1
				val[key] = unsafe { nil }
			}
		}
		else {
			return error('invalid map descriptor byte')
		}
	}
}

pub fn (mut d Decoder) decode_struct[T](mut val T) ! {
	data := d.buffer
	$for field in T.fields {
		// Decode each field using its type
		mut field_val := val.$(field.name)
		d.decode(data[d.pos..], mut field_val) or {
			return error('error decoding struct field: ${field.name}')
		}
		val[field.name] = field_val
	}
}

pub fn (mut d Decoder) decode_bool[T](mut val T) ! {
	val = d.bd == mp_true
	// d.pos +=
}

pub fn (mut d Decoder) decode_time[T](mut val T) ! {
	data := d.buffer
	$if T is time.Time || T is $int {
		match d.bd {
			mp_fix_ext_4 {
				/*
				timestamp 32 stores the number of seconds that have elapsed since 1970-01-01 00:00:00 UTC
					in an 32-bit unsigned integer:
					+--------+--------+--------+--------+--------+--------+
					|  0xd6  |   -1   |   seconds in 32-bit unsigned int  |
					+--------+--------+--------+--------+--------+--------+
				*/
				if data[d.pos] != u8(0xFF) {
					return error('invalid extension format')
				}
				data32 := binary.big_endian_u32(data[d.pos + 1..d.pos + 4])
				val = time.unix(i64(data32))
				d.pos += 5
			}
			mp_fix_ext_8 {
				/*
				timestamp 64 stores the number of seconds and nanoseconds that have elapsed since 1970-01-01 00:00:00 UTC
					in 32-bit unsigned integers:
					+--------+--------+--------+--------+--------+------|-+--------+--------+--------+--------+
					|  0xd7  |   -1   | nanosec. in 30-bit unsigned int |   seconds in 34-bit unsigned int    |
					+--------+--------+--------+--------+--------+------^-+--------+--------+--------+--------+
				*/
				if data[d.pos] != u8(0xFF) {
					return error('invalid extension format')
				}
				data64 := binary.big_endian_u64(data[d.pos + 1..d.pos + 8])
				sec := int(data64 & 0x00000003ffffffff)
				nsec := int(data64 >> 34)
				val = time.unix_nanosecond(i64(sec), nsec)
				d.pos += 8
			}
			mp_ext_8 {
				/*
				timestamp 96 stores the number of seconds and nanoseconds that have elapsed since 1970-01-01 00:00:00 UTC
					in 64-bit signed integer and 32-bit unsigned integer:
					+--------+--------+--------+--------+--------+--------+--------+
					|  0xc7  |   12   |   -1   |nanoseconds in 32-bit unsigned int |
					+--------+--------+--------+--------+--------+--------+--------+
					+--------+--------+--------+--------+--------+--------+--------+--------+
										seconds in 64-bit signed int                        |
					+--------+--------+--------+--------+--------+--------+--------+--------+
				*/

				if data[d.pos] != u8(0x0C) || data[d.pos + 4] != u8(0xFF) {
					return error('invalide extension format')
				}
				data32 := binary.big_endian_u32(data[d.pos + 1 + 4..d.pos + 12])
				data64 := binary.big_endian_u64(data[d.pos + 1 + 8..d.pos + 12])
				val = time.unix_nanosecond(i64(data64), data32)
				d.pos += 12
			}
			else {
				return error('invalid time descriptor byte')
			}
		}
	}
}

fn (mut d Decoder) read_str_len(data []u8) !int {
	match d.bd {
		mp_str_8 {
			return int(data[d.pos])
		}
		mp_str_16 {
			return int(binary.big_endian_u16(data[d.pos..d.pos + 2]))
		}
		mp_str_32 {
			return int(binary.big_endian_u32(data[d.pos..d.pos + 4]))
		}
		mp_fix_str_min...mp_fix_str_max {
			return data[d.pos - 1] - mp_fix_str_min
		}
		else {
			return error('invalid string length descriptor byte')
		}
	}
}

fn (mut d Decoder) read_bin_len(data []u8) !int {
	match d.bd {
		mp_bin_8 {
			return int(data[d.pos])
		}
		mp_bin_16 {
			return int(binary.big_endian_u16(data[d.pos..d.pos + 2]))
		}
		mp_bin_32 {
			return int(binary.big_endian_u32(data[d.pos..d.pos + 4]))
		}
		else {
			return error('invalid binary length descriptor byte')
		}
	}
}

fn (mut d Decoder) read_array_len(data []u8) !int {
	match d.bd {
		mp_array_16 {
			return int(binary.big_endian_u16(data[d.pos..d.pos + 2]))
		}
		mp_array_32 {
			return int(binary.big_endian_u32(data[d.pos..d.pos + 4]))
		}
		mp_fix_array_min...mp_fix_array_max {
			return data[d.pos - 1] - mp_fix_array_min
		}
		else {
			return error('invalid array length descriptor byte')
		}
	}
}

fn (mut d Decoder) read_map_len(data []u8) !int {
	match d.bd {
		mp_map_16 {
			return int(binary.big_endian_u16(data[d.pos..d.pos + 2]))
		}
		mp_map_32 {
			return int(binary.big_endian_u32(data[d.pos..d.pos + 4]))
		}
		mp_fix_map_min...mp_fix_map_max {
			return data[d.pos - 1] - mp_fix_map_min
		}
		else {
			return error('invalid map length descriptor byte')
		}
	}
}

fn (mut d Decoder) next() ! {
	if d.pos >= d.buffer.len {
		return error('unexpected end of data')
	}
	d.bd = d.buffer[d.pos]
	d.pos++
}
