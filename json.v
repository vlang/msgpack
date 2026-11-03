module msgpack

import encoding.base64
import math
import strings

// decode_to_json converts one MessagePack value to JSON text. See
// `Value.to_json` for how types without a JSON equivalent are written.
pub fn decode_to_json(data []u8, opts DecodeOpts) !string {
	return decode[Value](data, opts)!.to_json()!
}

// encode_to_json converts a V value to JSON text through its MessagePack
// encoding, which shows how MessagePack sees it: `[]u8` becomes base64,
// `time.Time` an RFC 3339 string, and so on (see `Value.to_json`).
pub fn encode_to_json[T](val T, opts EncodeOpts) !string {
	return decode_to_json(encode(val, opts)!)!
}

// to_json converts the value to JSON text. MessagePack types without a JSON
// equivalent are written as follows:
//   - bin: a base64 string
//   - ext: an object `{"type": <type>, "data": <base64 data>}`
//   - timestamp: an RFC 3339 string with nanoseconds, in UTC
//   - map keys that are not strings: the JSON text of the key, as a string
// It fails on values JSON cannot represent: NaN and infinite floats, str
// values that are not valid UTF-8, and maps whose keys would collide once
// converted (such as the integer 1 and the string "1").
pub fn (v Value) to_json() !string {
	mut sb := strings.new_builder(64)
	write_json(mut sb, v)!
	return sb.str()
}

fn write_json(mut sb strings.Builder, v Value) ! {
	match v {
		Nil {
			sb.write_string('null')
		}
		bool {
			sb.write_string(if v { 'true' } else { 'false' })
		}
		i64 {
			sb.write_string(v.str())
		}
		u64 {
			sb.write_string(v.str())
		}
		f32 {
			write_json_float(mut sb, f64(v), v.str())!
		}
		f64 {
			write_json_float(mut sb, v, v.str())!
		}
		string {
			if !utf8_valid(unsafe { v.str.vbytes(v.len) }, 0, v.len) {
				return error('msgpack: a str value is not valid UTF-8 and has no JSON representation')
			}
			write_json_string(mut sb, v)
		}
		[]u8 {
			write_json_string(mut sb, base64.encode(v))
		}
		[]Value {
			sb.write_u8(`[`)
			for i, item in v {
				if i > 0 {
					sb.write_u8(`,`)
				}
				write_json(mut sb, item)!
			}
			sb.write_u8(`]`)
		}
		Map {
			sb.write_u8(`{`)
			mut keys := map[string]bool{}
			for i, e in v.entries {
				if i > 0 {
					sb.write_u8(`,`)
				}
				key := if e.key is string { e.key } else { e.key.to_json()! }
				if key in keys {
					return error('msgpack: the JSON object would have the key "${key}" twice')
				}
				keys[key] = true
				write_json(mut sb, Value(key))!
				sb.write_u8(`:`)
				write_json(mut sb, e.value)!
			}
			sb.write_u8(`}`)
		}
		Ext {
			sb.write_string('{"type":${v.type_id},"data":')
			write_json_string(mut sb, base64.encode(v.data))
			sb.write_u8(`}`)
		}
		Timestamp {
			t := v.to_time()!
			write_json_string(mut sb, '${t.year:04d}-${t.month:02d}-${t.day:02d}T${t.hour:02d}:${t.minute:02d}:${t.second:02d}.${t.nanosecond:09d}Z')
		}
	}
}

fn write_json_float(mut sb strings.Builder, f f64, text string) ! {
	if math.is_nan(f) || math.is_inf(f, 0) {
		return error('msgpack: ${text} has no JSON representation')
	}
	sb.write_string(text)
}

fn write_json_string(mut sb strings.Builder, s string) {
	sb.write_u8(`"`)
	for c in s {
		match c {
			`"` {
				sb.write_string('\\"')
			}
			`\\` {
				sb.write_string('\\\\')
			}
			`\n` {
				sb.write_string('\\n')
			}
			`\r` {
				sb.write_string('\\r')
			}
			`\t` {
				sb.write_string('\\t')
			}
			else {
				if c < 0x20 {
					sb.write_string('\\u00')
					sb.write_u8('0123456789abcdef'[c >> 4])
					sb.write_u8('0123456789abcdef'[c & 0xf])
				} else {
					sb.write_u8(c)
				}
			}
		}
	}
	sb.write_u8(`"`)
}
