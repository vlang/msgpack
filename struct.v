module msgpack

import sync
import sync.stdatomic

// FieldOpts describes how a struct field is written.
struct FieldOpts {
	key string
}

// StructInfo describes how a struct type is written. It is computed once per
// type, so that attributes are not parsed again for every value.
struct StructInfo {
	fields []FieldOpts // in declaration order
	count  u32
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
	mut fields := []FieldOpts{}
	$for field in T.fields {
		fields << field_opts(field.name, field.attrs)
	}
	return &StructInfo{
		fields: fields
		count:  u32(fields.len)
	}
}

// field_opts returns how a field is written: under its name, or the name
// given by a `@[codec: 'name']` attribute.
fn field_opts(name string, attrs []string) FieldOpts {
	for attr in attrs {
		if attr.starts_with('codec:') {
			return FieldOpts{
				key: attr_value(attr)
			}
		}
	}
	return FieldOpts{
		key: name
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
	p.pack_map_header(info.count)
	mut idx := 0
	$for field in T.fields {
		p.put_key(info.fields[idx].key)
		$if field.typ is $option {
			if val.$(field.name) == none {
				p.pack_nil()
			} else {
				p.pack(unwrap_option(val.$(field.name)))!
			}
		} $else {
			p.pack(val.$(field.name))!
		}
		idx++
	}
}

fn (mut u Unpacker) unpack_struct_into[T](mut out T) ! {
	info := struct_info[T]()
	start := u.cur
	n := u.unpack_map_header()!
	u.enter(start)!
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
				if key_len == fo.key.len && unsafe { vmemcmp(key_ptr, fo.key.str, key_len) } == 0 {
					matched = true
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
	u.depth--
}
