module main

import encoding.hex
import json2
import math
import msgpack
import os

// testdata/msgpack-test-suite.json comes from
// https://github.com/kawanet/msgpack-test-suite (dist/, commit e04f6ed, MIT).
// Each case lists a value and every valid encoding of it, the most compact
// first.
const suite_path = os.join_path(@DIR, 'testdata', 'msgpack-test-suite.json')

fn test_every_encoding_of_the_msgpack_test_suite() {
	root := json2.decode[json2.Any](os.read_file(suite_path)!)!.as_map()
	mut checked := 0
	for file, cases in root {
		for c in cases.as_array() {
			case := c.as_map()
			encodings := case['msgpack'] or { json2.Null{} }
			for i, h in encodings.as_array() {
				data := hex.decode(h.str().replace('-', ''))!
				mut u := msgpack.new_unpacker(data)
				v := u.unpack_value()!
				assert u.done(), '${file} ${h}'
				assert matches_case(v, case), '${file} ${h}: decoded ${v}'
				if i == 0 {
					// Re-encoding uses the most compact size. On ties the bytes
					// may differ: max_i64 is listed as int 64, we write uint 64
					// like msgpack-c and msgpack-python.
					mut p := msgpack.new_packer()
					p.pack_value(v)!
					assert p.bytes().len == data.len, '${file} ${h}: re-encoded ${p.bytes().hex()}'
					mut r := msgpack.new_unpacker(p.bytes())
					assert matches_case(r.unpack_value()!, case), '${file} ${h}'
				}
				// skipping consumes exactly the same bytes
				mut s := msgpack.new_unpacker(data)
				s.skip_value()!
				assert s.done(), '${file} ${h}'
				checked++
			}
		}
	}
	assert checked == 233
}

fn matches_case(v msgpack.Value, case map[string]json2.Any) bool {
	if 'nil' in case {
		return v.is_nil()
	}
	if b := case['bool'] {
		return v.as_bool() or { return false } == b.bool()
	}
	if b := case['binary'] {
		return v.as_bin() or { return false } == hex.decode(b.str().replace('-', '')) or {
			return false
		}
	}
	if n := case['bignum'] {
		return match v {
			i64, u64 { v.str() == n.str() }
			f32 { f64(v) == n.str().f64() }
			f64 { v == n.str().f64() }
			else { false }
		}
	}
	if n := case['number'] {
		return v.as_f64() or { return false } == n.f64()
	}
	if s := case['string'] {
		return v.as_str() or { return false } == s.str()
	}
	if ts := case['timestamp'] {
		parts := ts.as_array()
		want := msgpack.Timestamp{
			seconds:     parts[0].i64()
			nanoseconds: u32(parts[1].i64())
		}
		return v is msgpack.Timestamp && v == want
	}
	if e := case['ext'] {
		parts := e.as_array()
		want_data := hex.decode(parts[1].str().replace('-', '')) or { return false }
		return v is msgpack.Ext && v.type_id == i8(parts[0].i64()) && v.data == want_data
	}
	if a := case['array'] {
		return matches_json(v, a)
	}
	if m := case['map'] {
		return matches_json(v, m)
	}
	return false
}

// matches_json compares a decoded value with the plain JSON used for arrays
// and maps in the suite.
fn matches_json(v msgpack.Value, want json2.Any) bool {
	match want {
		[]json2.Any {
			items := v.as_array() or { return false }
			if items.len != want.len {
				return false
			}
			for i, item in items {
				if !matches_json(item, want[i]) {
					return false
				}
			}
			return true
		}
		map[string]json2.Any {
			m := v.as_map() or { return false }
			if m.entries.len != want.len {
				return false
			}
			for key, item in want {
				if !matches_json(m.get(key) or { return false }, item) {
					return false
				}
			}
			return true
		}
		string {
			return v.as_str() or { return false } == want
		}
		bool {
			return v.as_bool() or { return false } == want
		}
		json2.Null {
			return v.is_nil()
		}
		else {
			f := v.as_f64() or { return false }
			return f == want.f64() || (math.is_nan(f) && math.is_nan(want.f64()))
		}
	}
}
