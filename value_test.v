module main

import encoding.hex
import msgpack

fn unpack_value(h string, opts msgpack.DecodeOpts) !msgpack.Value {
	mut u := msgpack.new_unpacker(hex.decode(h)!, opts)
	return u.unpack_value()!
}

fn test_value_helpers() {
	// {"name": "Ada", "tags": ["x", "y"], "age": 36, "big": 2^64-1, "ok": true, "none": nil}
	v := unpack_value('86' + 'a46e616d65a3416461' + 'a4746167739' + '2a178a179' + 'a361676524' +
		'a3626967cfffffffffffffffff' + 'a26f6bc3' + 'a46e6f6e65c0')!
	assert v.get('name')?.as_str()? == 'Ada'
	assert v.get('tags')?.at(1)?.as_str()? == 'y'
	assert v.get('tags')?.at(2) == none
	assert v.get('age')?.as_int()? == 36
	assert v.get('age')?.as_f64()? == 36.0
	assert v.get('big')?.as_uint()? == max_u64
	assert v.get('big')?.as_int() == none
	assert v.get('ok')?.as_bool()?
	assert v.get('none')?.is_nil()
	assert v.get('missing') == none
}

fn test_value_map_keeps_non_string_keys_order_and_duplicates() {
	// {1: "a", nil: "b", 1: "c"}
	v := unpack_value('83' + '01a161' + 'c0a162' + '01a163')!
	m := v.as_map()?
	assert m.entries.len == 3
	assert m.entries[0].key.as_int()? == 1
	assert m.entries[1].key.is_nil()
	assert m.entries[2].value.as_str()? == 'c'
	mut p := msgpack.new_packer()
	p.pack_value(v)!
	assert p.bytes().hex() == '8301a161c0a16201a163'
}

fn test_value_deny_duplicate_keys() {
	// the same key "a" written as fixstr then str 8, and 1 as fixint then uint 16
	for h in ['82a16101d9016102', '8201c0cd0001c0'] {
		if _ := unpack_value(h, deny_duplicate_keys: true) {
			assert false, h
		} else {
			assert err is msgpack.DuplicateKeyError
		}
		assert unpack_value(h)!.as_map()?.entries.len == 2
	}
}

fn test_value_timestamp_and_ext() {
	v := unpack_value('92' + 'd6ff5a4af6a5' + 'd40110')!
	assert v.at(0)? is msgpack.Timestamp
	assert v.at(1)? == msgpack.Value(msgpack.Ext{
		type_id: 1
		data:    [u8(0x10)]
	})
	// ext type -1 with a payload that is not a timestamp
	unpack_value('d5ff0000') or {
		assert err is msgpack.MalformedError
		return
	}
	assert false
}

fn test_value_max_depth() {
	nested := '91'.repeat(10) + 'c0'
	assert unpack_value(nested)!.at(0)?.at(0) != none
	mut u := msgpack.new_unpacker(hex.decode(nested)!, max_depth: 5)
	u.unpack_value() or {
		assert err is msgpack.MaxDepthError
		// the position is back at the start of the value
		assert u.pos() == 0
		return
	}
	assert false
}

fn test_value_deep_nesting_is_rejected_by_default() {
	data := hex.decode('91'.repeat(100_000) + 'c0')!
	mut u := msgpack.new_unpacker(data)
	u.unpack_value() or {
		assert err is msgpack.MaxDepthError
		return
	}
	assert false
}
