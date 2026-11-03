module msgpack

// Value holds any MessagePack value, for data whose shape is not known at
// compile time. Decode with `decode[msgpack.Value](data)!` and inspect it
// with the `as_*` helpers or a `match`.
//
// Integers decode to `i64`, except values above `max_i64` which decode to
// `u64`. Maps keep their entries in order, with keys of any type.
pub type Value = Ext
	| Map
	| Nil
	| Timestamp
	| []Value
	| []u8
	| bool
	| f32
	| f64
	| i64
	| string
	| u64

// Nil is the nil value.
pub struct Nil {}

// Map is a MessagePack map. Unlike a V map, it accepts keys of any type,
// keeps the order of its entries and preserves duplicate keys.
pub struct Map {
pub mut:
	entries []MapEntry
}

// MapEntry is one key/value pair of a Map.
pub struct MapEntry {
pub:
	key   Value
	value Value
}

// get returns the value of the first entry whose key is the string `key`.
pub fn (m Map) get(key string) ?Value {
	for e in m.entries {
		if e.key is string && e.key == key {
			return e.value
		}
	}
	return none
}

// is_nil reports whether the value is nil.
pub fn (v Value) is_nil() bool {
	return v is Nil
}

// as_bool returns the value if it is a boolean.
pub fn (v Value) as_bool() ?bool {
	return if v is bool { v } else { none }
}

// as_int returns the value if it is an integer that fits in i64.
pub fn (v Value) as_int() ?i64 {
	return match v {
		i64 { v }
		else { none }
	}
}

// as_uint returns the value if it is a non-negative integer.
pub fn (v Value) as_uint() ?u64 {
	return match v {
		u64 { v }
		i64 {
			if v >= 0 { u64(v) } else { none }
		}
		else { none }
	}
}

// as_f64 returns the value if it is a float, or an integer that converts
// exactly.
pub fn (v Value) as_f64() ?f64 {
	return match v {
		f64 { v }
		f32 { f64(v) }
		i64 {
			if int_is_exact(u64(v), v < 0, f64(v)) { f64(v) } else { none }
		}
		u64 {
			if int_is_exact(v, false, f64(v)) { f64(v) } else { none }
		}
		else { none }
	}
}

// as_str returns the value if it is a string.
pub fn (v Value) as_str() ?string {
	return if v is string { v } else { none }
}

// as_bin returns the value if it is binary data.
pub fn (v Value) as_bin() ?[]u8 {
	return if v is []u8 { v } else { none }
}

// as_array returns the elements if the value is an array.
pub fn (v Value) as_array() ?[]Value {
	return if v is []Value { v } else { none }
}

// as_map returns the value if it is a map.
pub fn (v Value) as_map() ?Map {
	return if v is Map { v } else { none }
}

// get returns the value for the string key `key` if the value is a map.
pub fn (v Value) get(key string) ?Value {
	return if v is Map { v.get(key) } else { none }
}

// at returns the element at `index` if the value is an array.
pub fn (v Value) at(index int) ?Value {
	if v is []Value {
		if index >= 0 && index < v.len {
			return v[index]
		}
	}
	return none
}

// unpack_value reads the next value, whatever its type. On error, the
// position is left at the start of that value.
pub fn (mut u Unpacker) unpack_value() !Value {
	start, depth := u.cur, u.depth
	return u.read_value() or {
		u.cur, u.depth = start, depth
		return err
	}
}

// read_value is recursive: it only dispatches, so that each nesting level
// keeps a small stack frame.
fn (mut u Unpacker) read_value() !Value {
	b := u.peek_byte()!
	if b in [u8(0xdc), 0xdd] || b & 0xf0 == 0x90 {
		return u.read_array_value()!
	}
	if b in [u8(0xde), 0xdf] || b & 0xf0 == 0x80 {
		return u.read_map_value()!
	}
	return u.read_scalar_value()!
}

fn (mut u Unpacker) read_array_value() !Value {
	start := u.cur
	n := u.unpack_array_header()!
	u.enter(start)!
	mut items := []Value{cap: n}
	for _ in 0 .. n {
		items << u.read_value()!
	}
	u.depth--
	return items
}

fn (mut u Unpacker) read_map_value() !Value {
	start := u.cur
	n := u.unpack_map_header()!
	u.enter(start)!
	mut m := Map{
		entries: []MapEntry{cap: n}
	}
	mut seen := map[string]bool{}
	for _ in 0 .. n {
		key_start := u.cur
		key := u.read_value()!
		if u.opts.deny_duplicate_keys {
			// Compare keys by value: re-encoding writes equal values with the
			// same bytes, whichever format the input used.
			mut kp := new_packer(initial_cap: 16)
			kp.pack_value(key)!
			canonical := kp.buf.bytestr()
			if canonical in seen {
				return DuplicateKeyError{
					pos: key_start
					key: key.str()
				}
			}
			seen[canonical] = true
		}
		m.entries << MapEntry{
			key:   key
			value: u.read_value()!
		}
	}
	u.depth--
	return m
}

@[noinline]
fn (mut u Unpacker) read_scalar_value() !Value {
	match u.peek_kind()! {
		.nil_val {
			u.cur++
			return Nil{}
		}
		.bool_val {
			return u.unpack_bool()!
		}
		.int_val, .uint_val {
			bits, negative := u.read_integer()!
			if !negative && bits > u64(max_i64) {
				return bits
			}
			return i64(bits)
		}
		.f32_val {
			return u.unpack_f32()!
		}
		.f64_val {
			return u.unpack_f64()!
		}
		.str_val {
			return u.unpack_str()!
		}
		.bin_val {
			return u.unpack_bin()!
		}
		.ext_val {
			start := u.cur
			ext := u.unpack_ext()!
			if ext.type_id == timestamp_ext_type {
				u.cur = start
				return u.unpack_timestamp()!
			}
			return ext
		}
		.array_val, .map_val {
			return error('msgpack: containers are decoded by read_value')
		}
	}
}

// pack_value writes a Value.
pub fn (mut p Packer) pack_value(v Value) ! {
	match v {
		Nil {
			p.pack_nil()
		}
		bool {
			p.pack_bool(v)
		}
		i64 {
			p.pack_int(v)
		}
		u64 {
			p.pack_uint(v)
		}
		f32 {
			p.pack_f32(v)
		}
		f64 {
			p.pack_f64(v)
		}
		string {
			p.pack_str(v)!
		}
		[]u8 {
			p.pack_bin(v)!
		}
		[]Value {
			p.pack_array_header(check_count(v.len)!)
			for item in v {
				p.pack_value(item)!
			}
		}
		Map {
			p.pack_map_header(check_count(v.entries.len)!)
			for e in v.entries {
				p.pack_value(e.key)!
				p.pack_value(e.value)!
			}
		}
		Ext {
			p.pack_ext(v.type_id, v.data)!
		}
		Timestamp {
			p.pack_timestamp(v)!
		}
	}
}

// enter records one more level of nesting for the container starting at
// `start`, and fails once `opts.max_depth` is exceeded.
@[inline]
fn (mut u Unpacker) enter(start int) ! {
	u.depth++
	if u.depth > u.opts.max_depth {
		return MaxDepthError{
			pos:       start
			max_depth: u.opts.max_depth
		}
	}
}
