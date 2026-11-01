module msgpack

import time

// encode serializes `val` to MessagePack.
//
// Supported types: bool, integers, floats, string, []u8 (as bin), arrays,
// fixed arrays, maps, structs, enums, Options (`none` is nil), `time.Time`
// (as a timestamp), type aliases of these, and `Value`, `Ext`, `Timestamp`,
// `RawMessage`. Types implementing `Marshaler` and `Unmarshaler` choose their
// own representation. Using another type is a compile-time error.
//
// A struct is written as a map from field names to values. Attributes
// change how a field is written:
//   - `@[msgpack.Key: 'name']` uses another key
//   - `@[skip]` or `@[msgpack.Key: '-']` leaves the field out
//   - `@[omitempty]` leaves the field out when it is none, zero, false or
//     empty
//   - `@[required]` makes decoding fail when the field is missing
// and on the struct itself:
//   - `@[msgpack.RenameAll: 'camelCase']` renames every field; also
//     `snake_case`, `PascalCase`, `kebab-case` and `SCREAMING_SNAKE_CASE`
//   - `@[msgpack.AsArray]` writes the fields as an array, in declaration
//     order, like rmp-serde and the `as_array` option of Go libraries
pub fn encode[T](val T, opts EncodeOpts) ![]u8 {
	mut p := new_packer(opts)
	p.pack(val)!
	return p.buf
}

// decode deserializes one MessagePack value into a `T`. It fails if the data
// holds anything after that value, unless `opts.allow_trailing_bytes` is set.
pub fn decode[T](data []u8, opts DecodeOpts) !T {
	mut u := new_unpacker(data, opts)
	val := u.unpack[T]()!
	if !opts.allow_trailing_bytes && !u.done() {
		return malformed(u.cur, '${u.remaining()} trailing byte(s) after the value')
	}
	return val
}

// pack writes `val`, choosing the MessagePack type from the V type at
// compile time. See `encode` for the supported types.
pub fn (mut p Packer) pack[T](val T) ! {
	$if T is RawMessage {
		p.pack_raw(val)!
	} $else $if T is Marshaler {
		p.pack_marshaler(val)!
	} $else $if T is Value {
		p.pack_value(val)!
	} $else $if T is Ext {
		p.pack_ext(val.type_id, val.data)!
	} $else $if T is Timestamp {
		p.pack_timestamp(val)!
	} $else $if T is time.Time {
		p.pack_time(val)!
	} $else $if T is $option {
		if val == none {
			p.pack_nil()
		} else {
			p.pack(unwrap_option(val))!
		}
	} $else $if T.unaliased_typ is string {
		p.pack_str(string(val))!
	} $else $if T.unaliased_typ is bool {
		p.pack_bool(bool(val))
	} $else $if T.unaliased_typ is i8 {
		p.pack_int(i64(val))
	} $else $if T.unaliased_typ is i16 {
		p.pack_int(i64(val))
	} $else $if T.unaliased_typ is int {
		p.pack_int(i64(val))
	} $else $if T.unaliased_typ is i32 {
		p.pack_int(i64(val))
	} $else $if T.unaliased_typ is i64 {
		p.pack_int(i64(val))
	} $else $if T.unaliased_typ is isize {
		p.pack_int(i64(val))
	} $else $if T.unaliased_typ is u8 {
		p.pack_uint(u64(val))
	} $else $if T.unaliased_typ is u16 {
		p.pack_uint(u64(val))
	} $else $if T.unaliased_typ is u32 {
		p.pack_uint(u64(val))
	} $else $if T.unaliased_typ is u64 {
		p.pack_uint(u64(val))
	} $else $if T.unaliased_typ is usize {
		p.pack_uint(u64(val))
	} $else $if T.unaliased_typ is uint {
		p.pack_uint(u64(val))
	} $else $if T.unaliased_typ is f32 {
		p.pack_f32(f32(val))
	} $else $if T.unaliased_typ is f64 {
		p.pack_f64(f64(val))
	} $else $if T is $enum {
		if p.opts.enum_as_string && !is_flag_enum[T]() {
			p.pack_str(val.str())!
		} else {
			p.pack_int(i64(val))
		}
	} $else $if T.unaliased_typ is []u8 {
		p.pack_bin(val)!
	} $else $if T.unaliased_typ is $array_fixed {
		p.pack_array_header(check_count(val.len)!)
		for i in 0 .. val.len {
			p.pack(val[i])!
		}
	} $else $if T.unaliased_typ is $array {
		p.pack_array_header(check_count(val.len)!)
		for item in val {
			p.pack(item)!
		}
	} $else $if T.unaliased_typ is $map {
		p.pack_map_header(check_count(val.len)!)
		if p.opts.sort_keys && val.len > 1 {
			for k in sorted_keys(val) {
				p.pack(k)!
				p.pack(val[k])!
			}
		} else {
			for k, item in val {
				p.pack(k)!
				p.pack(item)!
			}
		}
	} $else $if T is $struct {
		p.pack_struct(val)!
	} $else $if T is IError {
		// Never reached: the old V compiler instantiates the field loop of an
		// empty struct with IError, which must not stop the compilation.
		return error('msgpack: errors cannot be encoded')
	} $else {
		$compile_error('msgpack: this type cannot be encoded; see `encode` for the supported types')
	}
}

// sorted_keys returns the keys of `m` in ascending order when they are
// strings or numbers, and in insertion order otherwise.
fn sorted_keys[K, V](m map[K]V) []K {
	mut keys := m.keys()
	$if K is string || K is $int || K is $float {
		keys.sort()
	}
	return keys
}

// unwrap_option returns the value of an Option known to hold one. It exists
// so that V infers the payload type at the comptime call site.
fn unwrap_option[T](val ?T) T {
	return val or { T{} }
}

// unpack reads the next value into a `T`, converting between compatible
// MessagePack and V types: any integer format to any V integer type that
// holds the value, float32 or float64 to either float type, str or bin to
// string or []u8, int or str (the member name) to an enum. On error, the
// position is left at the start of the value.
pub fn (mut u Unpacker) unpack[T]() !T {
	start, depth := u.cur, u.depth
	return u.read[T]() or {
		u.cur, u.depth = start, depth
		return err
	}
}

fn (mut u Unpacker) read[T]() !T {
	$if T is RawMessage {
		return u.unpack_raw()!
	} $else $if T is Unmarshaler {
		return u.read_unmarshaler[T]()!
	} $else $if T is Value {
		return u.read_value()!
	} $else $if T is Ext {
		return u.unpack_ext()!
	} $else $if T is Timestamp {
		return u.unpack_timestamp()!
	} $else $if T is time.Time {
		return u.unpack_time()!
	} $else $if T.unaliased_typ is string {
		return T(u.unpack_text()!)
	} $else $if T.unaliased_typ is bool {
		return T(u.unpack_bool()!)
	} $else $if T.unaliased_typ is i8 {
		return T(i8(u.unpack_int_in('i8', min_i8, max_i8)!))
	} $else $if T.unaliased_typ is i16 {
		return T(i16(u.unpack_int_in('i16', min_i16, max_i16)!))
	} $else $if T.unaliased_typ is int {
		return T(int(u.unpack_int_in('int', min_int, max_int)!))
	} $else $if T.unaliased_typ is i32 {
		return T(i32(u.unpack_int_in('i32', min_i32, max_i32)!))
	} $else $if T.unaliased_typ is i64 {
		return T(u.unpack_int()!)
	} $else $if T.unaliased_typ is isize {
		lo, hi := signed_bounds(sizeof(T))
		return T(u.unpack_int_in('isize', lo, hi)!)
	} $else $if T.unaliased_typ is u8 {
		return T(u8(u.unpack_uint_to('u8', max_u8)!))
	} $else $if T.unaliased_typ is u16 {
		return T(u16(u.unpack_uint_to('u16', max_u16)!))
	} $else $if T.unaliased_typ is u32 {
		return T(u32(u.unpack_uint_to('u32', max_u32)!))
	} $else $if T.unaliased_typ is u64 {
		return T(u.unpack_uint()!)
	} $else $if T.unaliased_typ is usize {
		return T(u.unpack_uint_to('usize', unsigned_max(sizeof(T)))!)
	} $else $if T.unaliased_typ is uint {
		return T(u.unpack_uint_to('uint', unsigned_max(sizeof(T)))!)
	} $else $if T.unaliased_typ is f32 {
		return T(u.unpack_f32()!)
	} $else $if T.unaliased_typ is f64 {
		return T(u.unpack_f64()!)
	} $else $if T is $enum {
		return u.unpack_enum[T]()!
	} $else $if T.unaliased_typ is []u8 {
		return T(u.unpack_bytes()!)
	} $else $if T.unaliased_typ is $array_fixed {
		mut out := T{}
		u.unpack_fixed_array_into(mut out)!
		return out
	} $else $if T.unaliased_typ is $array {
		mut out := T{}
		u.unpack_array_into(mut out)!
		return out
	} $else $if T.unaliased_typ is $map {
		mut out := T{}
		unpack_map_into(mut u, mut out)!
		return out
	} $else $if T is $struct {
		mut out := T{}
		u.unpack_struct_into(mut out)!
		return out
	} $else $if T is IError {
		// Never reached; see the IError branch of `pack`.
		return error('msgpack: errors cannot be decoded')
	} $else {
		$compile_error('msgpack: this type cannot be decoded; see `encode` for the supported types')
	}
}

// unpack_into reads the next value into `out`. Taking `out` as a mut
// parameter lets V infer T at `unpack_into(mut val.$(field.name))`.
@[inline]
fn (mut u Unpacker) unpack_into[T](mut out T) ! {
	out = u.read[T]()!
}

// unpack_text reads a str, or a bin as most implementations allow.
fn (mut u Unpacker) unpack_text() !string {
	if u.cur < u.data.len && u.data[u.cur] in [u8(0xc4), 0xc5, 0xc6] {
		start := u.cur
		bytes := u.unpack_bin()!
		if u.opts.validate_utf8 && !utf8_valid(bytes, 0, bytes.len) {
			u.cur = start
			return InvalidUtf8Error{
				pos: start
			}
		}
		return bytes.bytestr()
	}
	return u.unpack_str()!
}

// unpack_bytes reads a bin, or the bytes of a str.
fn (mut u Unpacker) unpack_bytes() ![]u8 {
	if u.cur < u.data.len && u.data[u.cur] in [u8(0xc4), 0xc5, 0xc6] {
		return u.unpack_bin()!
	}
	ptr, len := u.read_str_view()!
	return unsafe { ptr.vbytes(len) }.clone()
}

fn (mut u Unpacker) unpack_int_in(target string, min i64, max i64) !i64 {
	start := u.cur
	v := u.unpack_int()!
	if v < min || v > max {
		u.cur = start
		return int_range(start, target, v.str())
	}
	return v
}

fn (mut u Unpacker) unpack_uint_to(target string, max u64) !u64 {
	start := u.cur
	bits, negative := u.read_integer()!
	if negative || bits > max {
		u.cur = start
		return int_range(start, target, if negative { i64(bits).str() } else { bits.str() })
	}
	return bits
}

// is_flag_enum reports whether the enum T has the `@[flag]` attribute.
fn is_flag_enum[T]() bool {
	$for attr in T.attributes {
		if attr.name == 'flag' {
			return true
		}
	}
	return false
}

// unpack_enum reads an enum from its integer value or its member name. Flag
// enums accept any combination of their members as an integer, and a
// single member by name.
//
// The members of a flag enum are the bits 1, 2, 4... in declaration order.
// Their values are computed from their position: V3 reports wrong values for
// them in `$for member in T.values`.
fn (mut u Unpacker) unpack_enum[T]() !T {
	start := u.cur
	is_flag := is_flag_enum[T]()
	if u.peek_kind()! == .str_val {
		name := u.unpack_str()!
		mut idx := 0
		$for member in T.values {
			if member.name == name {
				return if is_flag { unsafe { T(i64(1) << idx) } } else { member.value }
			}
			idx++
		}
		u.cur = start
		return TypeMismatchError{
			pos:      start
			expected: T.name
			got:      'unknown member "${name}"'
		}
	}
	v := u.unpack_int()!
	if is_flag {
		mut count := 0
		$for _ in T.values {
			count++
		}
		all := (i64(1) << count) - 1
		if v >= 0 && v & ~all == 0 {
			return unsafe { T(v) }
		}
	} else {
		$for member in T.values {
			if i64(member.value) == v {
				return member.value
			}
		}
	}
	u.cur = start
	return TypeMismatchError{
		pos:      start
		expected: T.name
		got:      'unknown value ${v}'
	}
}

fn (mut u Unpacker) unpack_array_into[E](mut out []E) ! {
	start := u.cur
	n := u.unpack_array_header()!
	u.enter(start)!
	out = []E{cap: n}
	for i in 0 .. n {
		out << u.read[E]() or { return with_path(err, '[${i}]') }
	}
	u.depth--
}

fn (mut u Unpacker) unpack_fixed_array_into[T](mut out T) ! {
	start := u.cur
	n := u.unpack_array_header()!
	if n != out.len {
		u.cur = start
		return TypeMismatchError{
			pos:      start
			expected: 'array of ${out.len} elements'
			got:      'array of ${n} elements'
		}
	}
	u.enter(start)!
	for i in 0 .. n {
		u.unpack_into(mut out[i]) or { return with_path(err, '[${i}]') }
	}
	u.depth--
}

// unpack_map_into is a function rather than a method: V infers both type
// parameters reliably only in that form.
fn unpack_map_into[K, V](mut u Unpacker, mut out map[K]V) ! {
	start := u.cur
	n := u.unpack_map_header()!
	u.enter(start)!
	for _ in 0 .. n {
		key_start := u.cur
		key := u.read[K]()!
		if u.opts.deny_duplicate_keys && key in out {
			return DuplicateKeyError{
				pos: key_start
				key: '${key}'
			}
		}
		out[key] = u.read[V]() or { return with_path(err, '[${key}]') }
	}
	u.depth--
}

// with_path prefixes the location of a decoding error with `segment`: a
// field name or an `[index]`.
fn with_path(err IError, segment string) IError {
	match err {
		TypeMismatchError {
			return TypeMismatchError{
				...err
				path: join_path(segment, err.path)
			}
		}
		MissingFieldError {
			return MissingFieldError{
				...err
				path: join_path(segment, err.path)
			}
		}
		IntRangeError {
			return IntRangeError{
				...err
				path: join_path(segment, err.path)
			}
		}
		UnknownFieldError {
			return UnknownFieldError{
				...err
				path: join_path(segment, err.path)
			}
		}
		DuplicateKeyError {
			return DuplicateKeyError{
				...err
				path: join_path(segment, err.path)
			}
		}
		else {
			return err
		}
	}
}

fn join_path(segment string, rest string) string {
	if rest == '' {
		return segment
	}
	return if rest.starts_with('[') { segment + rest } else { '${segment}.${rest}' }
}

// signed_bounds returns the range of a signed integer type `size` bytes wide.
// The platform-width types are bounded by their actual size rather than by
// named constants, which do not exist for every width.
fn signed_bounds(size u32) (i64, i64) {
	if size >= 8 {
		return min_i64, max_i64
	}
	half := i64(1) << (size * 8 - 1)
	return -half, half - 1
}

// unsigned_max returns the largest value of an unsigned integer type `size` bytes wide.
fn unsigned_max(size u32) u64 {
	if size >= 8 {
		return max_u64
	}
	return (u64(1) << (size * 8)) - 1
}
