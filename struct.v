module msgpack

import sync
import sync.stdatomic
import time

// FieldOpts describes how a struct field is written, from its attributes.
struct FieldOpts {
	key       string
	skip      bool
	omitempty bool
	required  bool
}

// StructInfo describes how a struct type is written. It is computed once per
// type, so that attributes are not parsed again for every value.
struct StructInfo {
	fields        []FieldOpts // in declaration order
	as_array      bool
	count         u32 // fields that are not skipped
	has_omitempty bool
	has_required  bool
	// duplicate_key is set when two fields use the same key, which makes the
	// struct impossible to encode or decode unambiguously.
	duplicate_key string
}

// struct_info returns the StructInfo of T, computed on first use and then
// shared by all threads.
fn struct_info[T]() &StructInfo {
	idx := typeof[T]().idx
	name := typeof[T]().name
	ptr := stdatomic.load_u64(unsafe { &struct_infos.published })
	if ptr != 0 {
		infos := unsafe { &StructInfoMap(voidptr(ptr)) }
		if entries := infos.by_type[idx] {
			for e in entries {
				if e.name == name {
					return e.info
				}
			}
		}
	}
	return add_struct_info[T](idx, name)
}

// StructInfoCache holds the StructInfo of every struct type met so far. The
// map is never modified once published: a new type publishes a new map, with
// an atomic store that readers pair with an atomic load. Readers take no lock.
struct StructInfoCache {
mut:
	mu        &sync.Mutex    = sync.new_mutex()
	current   &StructInfoMap = unsafe { nil } // keeps the published map reachable
	published u64 // address of `current`
}

struct StructInfoMap {
	// keyed by type index, with the type name to tell apart types whose index
	// collides
	by_type map[int][]NamedStructInfo
}

struct NamedStructInfo {
	name string
	info &StructInfo
}

// struct_infos is created when the module is initialized, before any thread.
const struct_infos = &StructInfoCache{}

fn add_struct_info[T](idx int, name string) &StructInfo {
	mut cache := unsafe { struct_infos }
	cache.mu.lock()
	defer {
		cache.mu.unlock()
	}
	mut by_type := map[int][]NamedStructInfo{}
	if !isnil(cache.current) {
		// another thread may have added T meanwhile
		if entries := cache.current.by_type[idx] {
			for e in entries {
				if e.name == name {
					return e.info
				}
			}
		}
		for k, v in cache.current.by_type {
			by_type[k] = v
		}
	}
	info := new_struct_info[T]()
	mut entries := (by_type[idx] or { []NamedStructInfo{} }).clone()
	entries << NamedStructInfo{name, info}
	by_type[idx] = entries
	next := &StructInfoMap{
		by_type: by_type
	}
	cache.current = next
	stdatomic.store_u64(&cache.published, u64(voidptr(next)))
	return info
}

fn new_struct_info[T]() &StructInfo {
	mut as_array := false
	mut rename := ''
	$for attr in T.attributes {
		if attr.name == 'msgpack.AsArray' {
			as_array = true
		} else if attr.name == 'msgpack.RenameAll' {
			rename = attr.arg
		}
	}
	mut fields := []FieldOpts{}
	mut count := u32(0)
	mut has_omitempty := false
	mut has_required := false
	mut keys := map[string]bool{}
	mut duplicate_key := ''
	$for field in T.fields {
		fo := field_opts(field.name, field.attrs, if as_array { '' } else { rename })
		fields << fo
		if !fo.skip {
			count++
			has_omitempty = has_omitempty || fo.omitempty
			has_required = has_required || fo.required
			if !as_array && fo.key in keys && duplicate_key == '' {
				duplicate_key = fo.key
			}
			keys[fo.key] = true
		}
	}
	return &StructInfo{
		fields:        fields
		as_array:      as_array
		count:         count
		has_omitempty: has_omitempty && !as_array
		has_required:  has_required
		duplicate_key: duplicate_key
	}
}

fn duplicate_field_key[T](key string) IError {
	return error('msgpack: two fields of ${T.name} use the key "${key}"')
}

fn field_opts(name string, attrs []string, rename string) FieldOpts {
	if attrs.len == 0 && rename.len == 0 {
		return FieldOpts{
			key: name
		}
	}
	mut key := ''
	mut skip := false
	mut omitempty := false
	mut required := false
	for attr in attrs {
		if attr == 'skip' {
			skip = true
		} else if attr == 'omitempty' {
			omitempty = true
		} else if attr == 'required' {
			required = true
		} else if attr.starts_with('msgpack.Key:') {
			v := attr_value(attr)
			if v == '-' {
				skip = true
			} else if v != '' {
				key = v
			}
		}
	}
	if key == '' {
		key = if rename == '' { name } else { rename_field(name, rename) }
	}
	return FieldOpts{
		key:       key
		skip:      skip
		omitempty: omitempty
		required:  required
	}
}

// attr_value returns the value of a `key: value` attribute, without quotes.
fn attr_value(attr string) string {
	mut v := attr.all_after(':').trim_space()
	if v.len >= 2 && ((v[0] == `'` && v[v.len - 1] == `'`) || (v[0] == `"` && v[v.len - 1] == `"`)) {
		v = v[1..v.len - 1]
	}
	return v
}

fn (mut p Packer) pack_struct[T](val T) ! {
	info := struct_info[T]()
	if info.duplicate_key != '' {
		return duplicate_field_key[T](info.duplicate_key)
	}
	mut count := info.count
	if info.has_omitempty {
		mut idx := 0
		$for field in T.fields {
			fo := info.fields[idx]
			if fo.omitempty && !fo.skip {
				$if field.typ is $option {
					if val.$(field.name) == none {
						count--
					}
				} $else {
					if is_empty(val.$(field.name)) {
						count--
					}
				}
			}
			idx++
		}
	}
	if info.as_array {
		p.pack_array_header(count)
	} else {
		p.pack_map_header(count)
	}
	mut idx := 0
	$for field in T.fields {
		fo := info.fields[idx]
		mut write := !fo.skip
		if write && fo.omitempty && info.has_omitempty {
			$if field.typ is $option {
				write = val.$(field.name) != none
			} $else {
				write = !is_empty(val.$(field.name))
			}
		}
		if write {
			if !info.as_array {
				p.put_key(fo.key)
			}
			$if field.typ is $option {
				if val.$(field.name) == none {
					p.pack_nil()
				} else {
					p.pack(unwrap_option(val.$(field.name)))!
				}
			} $else {
				p.pack(val.$(field.name))!
			}
		}
		idx++
	}
}

// is_empty reports whether `@[omitempty]` leaves a value out: zero numbers,
// false, empty strings, arrays and maps, the zero time and enum values equal
// to 0. Structs are never empty.
fn is_empty[T](v T) bool {
	$if T.unaliased_typ is string {
		s := string(v)
		return s.len == 0
	} $else $if T.unaliased_typ is bool {
		return !bool(v)
	} $else $if T is $enum {
		return i64(v) == 0
	} $else $if T.unaliased_typ is $int {
		return i64(v) == 0
	} $else $if T.unaliased_typ is $float {
		return f64(v) == 0
	} $else $if T.unaliased_typ is $array || T.unaliased_typ is $map {
		return v.len == 0
	} $else $if T is time.Time {
		return v == time.Time{}
	} $else {
		return false
	}
}

fn (mut u Unpacker) unpack_struct_into[T](mut out T) ! {
	info := struct_info[T]()
	if info.duplicate_key != '' {
		return duplicate_field_key[T](info.duplicate_key)
	}
	if info.as_array {
		u.unpack_struct_array_into(mut out, info)!
		return
	}
	start := u.cur
	n := u.unpack_map_header()!
	u.enter(start)!
	mut found := if info.has_required { []bool{len: info.fields.len} } else { []bool{} }
	mut seen := map[string]bool{}
	for _ in 0 .. n {
		key_start := u.cur
		key_ptr, key_len := u.read_str_view()!
		if u.opts.deny_duplicate_keys {
			key := unsafe { tos(key_ptr, key_len) }.clone()
			if key in seen {
				return DuplicateKeyError{
					pos: key_start
					key: key
				}
			}
			seen[key] = true
		}
		mut matched := false
		mut idx := 0
		$for field in T.fields {
			if !matched {
				fo := info.fields[idx]
				if !fo.skip && key_len == fo.key.len
					&& unsafe { vmemcmp(key_ptr, fo.key.str, key_len) } == 0 {
					matched = true
					if info.has_required {
						found[idx] = true
					}
					$if field.typ is Value {
						// assigned directly: the old V compiler passes a sum type
						// field to a mut parameter by copy
						out.$(field.name) = u.read_value() or { return with_path(err, field.name) }
					} $else $if field.typ is $option {
						if u.try_unpack_nil() {
							out.$(field.name) = none
						} else {
							mut inner := $zero(field.typ.payload_type)
							u.unpack_into(mut inner) or { return with_path(err, field.name) }
							out.$(field.name) = inner
						}
					} $else {
						u.unpack_into(mut out.$(field.name)) or {
							return with_path(err, field.name)
						}
					}
				}
			}
			idx++
		}
		if !matched {
			if u.opts.deny_unknown_fields {
				return UnknownFieldError{
					pos:  key_start
					name: unsafe { tos(key_ptr, key_len) }.clone()
				}
			}
			u.skip_value()!
		}
	}
	if info.has_required {
		for i, fo in info.fields {
			if fo.required && !fo.skip && !found[i] {
				return MissingFieldError{
					pos:  start
					name: fo.key
				}
			}
		}
	}
	u.depth--
}

// unpack_struct_array_into reads a struct written with `@[msgpack.AsArray]`:
// one element per field that is not skipped, in declaration order. Missing
// trailing elements leave their fields unchanged, extra elements are skipped.
fn (mut u Unpacker) unpack_struct_array_into[T](mut out T, info &StructInfo) ! {
	start := u.cur
	n := u.unpack_array_header()!
	u.enter(start)!
	mut i := 0
	mut idx := 0
	$for field in T.fields {
		fo := info.fields[idx]
		idx++
		if !fo.skip {
			if i < n {
				$if field.typ is Value {
					out.$(field.name) = u.read_value() or { return with_path(err, field.name) }
				} $else $if field.typ is $option {
					if u.try_unpack_nil() {
						out.$(field.name) = none
					} else {
						mut inner := $zero(field.typ.payload_type)
						u.unpack_into(mut inner) or { return with_path(err, field.name) }
						out.$(field.name) = inner
					}
				} $else {
					u.unpack_into(mut out.$(field.name)) or {
						return with_path(err, field.name)
					}
				}
			} else if fo.required {
				return MissingFieldError{
					pos:  start
					name: field.name
				}
			}
			i++
		}
	}
	for ; i < n; i++ {
		if u.opts.deny_unknown_fields {
			return UnknownFieldError{
				pos:  u.cur
				name: '[${i}]'
			}
		}
		u.skip_value()!
	}
	u.depth--
}

// rename_field converts a V field name (snake_case) for
// `@[msgpack.RenameAll]`.
fn rename_field(name string, strategy string) string {
	return match strategy {
		'camelCase' { camel_case(name, false) }
		'PascalCase' { camel_case(name, true) }
		'kebab-case' { name.replace('_', '-') }
		'SCREAMING_SNAKE_CASE' { name.to_upper() }
		else { name }
	}
}

fn camel_case(name string, upper_first bool) string {
	mut out := []u8{cap: name.len}
	mut upper := upper_first
	for c in name {
		if c == `_` {
			upper = out.len > 0
			continue
		}
		out << if upper && c >= `a` && c <= `z` { c - 32 } else { c }
		upper = false
	}
	return out.bytestr()
}
