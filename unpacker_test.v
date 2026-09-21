module main

import encoding.hex
import msgpack

fn unpacker(h string) msgpack.Unpacker {
	return msgpack.new_unpacker(hex.decode(h) or { panic(err) })
}

fn test_unpack_integers_every_format() {
	cases := {
		'00':                 i64(0)
		'7f':                 127
		'ff':                 -1
		'e0':                 -32
		'cc80':               128
		'ccff':               255
		'cd0100':             256
		'cdffff':             65535
		'ce00010000':         65536
		'ceffffffff':         4294967295
		'cf0000000100000000': 4294967296
		'cf7fffffffffffffff': max_i64
		'd080':               -128
		'd07f':               127
		'd18000':             -32768
		'd280000000':         -2147483648
		'd38000000000000000': min_i64
		'd3ffffffffffffffff': -1
	}
	for h, want in cases {
		mut u := unpacker(h)
		assert u.unpack_int()! == want, h
		assert u.done(), h
	}
	mut u := unpacker('cfffffffffffffffff')
	assert u.unpack_uint()! == max_u64
}

fn test_unpack_integer_range_errors() {
	mut u := unpacker('cfffffffffffffffff')
	u.unpack_int() or {
		assert err is msgpack.IntRangeError
		assert u.pos() == 0
		return
	}
	assert false
}

fn test_unpack_uint_rejects_negative() {
	mut u := unpacker('ff')
	u.unpack_uint() or {
		assert err is msgpack.IntRangeError
		return
	}
	assert false
}

fn test_unpack_nil_and_bool() {
	mut u := unpacker('c0c2c3')
	assert u.try_unpack_nil()
	assert !u.try_unpack_nil()
	assert u.unpack_bool()! == false
	assert u.unpack_bool()! == true
	assert u.done()
	mut bad := unpacker('00')
	bad.unpack_bool() or {
		assert err is msgpack.TypeMismatchError
		assert err.msg().contains('expected bool, got uint')
		return
	}
	assert false
}

fn test_unpack_floats() {
	mut u := unpacker('ca4048f5c3cb40091eb851eb851f2a')
	assert u.unpack_f32()! == f32(3.14)
	assert u.unpack_f64()! == 3.14
	assert u.unpack_f64()! == 42.0 // exact integers are accepted as floats
	mut w := unpacker('cb40091eb851eb851f')
	assert w.unpack_f32()! == f32(3.14) // float64 rounded to float32
	// integers convert only when the float type holds them exactly
	mut exact := unpacker('cf0040000000000000' + 'ce01000000')
	assert exact.unpack_f64()! == 18014398509481984.0 // 2^54
	assert exact.unpack_f32()! == 16777216.0 // 2^24
	for h, target in {
		'cf0020000000000001': 'f64' // 2^53 + 1
		'ce01000001':         'f32' // 2^24 + 1
	} {
		mut u2 := unpacker(h)
		if target == 'f64' {
			if _ := u2.unpack_f64() {
				assert false, h
			}
		} else {
			if _ := u2.unpack_f32() {
				assert false, h
			}
		}
		assert u2.pos() == 0
	}
	mut s := unpacker('a0')
	if _ := s.unpack_f64() {
		assert false
	} else {
		assert err is msgpack.TypeMismatchError
	}
}

fn test_unpack_str_every_format() {
	for h in ['a3616263', 'd903616263', 'da0003616263', 'db00000003616263'] {
		mut u := unpacker(h)
		assert u.unpack_str()! == 'abc', h
		assert u.done(), h
	}
	long := 'x'.repeat(40)
	mut u := unpacker('d928' + long.bytes().hex())
	assert u.unpack_str()! == long
	mut empty := unpacker('a0')
	assert empty.unpack_str()! == ''
}

fn test_unpack_str_validates_utf8() {
	mut u := unpacker('a2c328')
	u.unpack_str() or {
		assert err is msgpack.InvalidUtf8Error
		assert u.pos() == 0
		mut lax := msgpack.new_unpacker(hex.decode('a2c328')!, validate_utf8: false)
		assert lax.unpack_str()!.bytes() == [u8(0xc3), 0x28]
		return
	}
	assert false
}

fn test_unpack_bin_every_format() {
	for h in ['c403010203', 'c50003010203', 'c600000003010203'] {
		mut u := unpacker(h)
		assert u.unpack_bin()! == [u8(1), 2, 3], h
		assert u.done(), h
	}
}

fn test_unpack_containers() {
	mut u := unpacker('93' + 'dc0001' + 'dd00000000' + '82' + 'de0000' + 'df00000001')
	assert u.unpack_array_header()! == 3
	assert u.unpack_array_header()! == 1
	assert u.unpack_array_header()! == 0
	assert u.unpack_map_header()! == 2
	assert u.unpack_map_header()! == 0
	assert u.pos() == 13
}

fn test_unpack_ext_every_format() {
	cases := {
		'd40110':                 1
		'd5022021':               2
		'd60330313233':           4
		'd7043031323334353637':   8
		'd805' + '00'.repeat(16): 16
		'c7000a':                 0
		'c7030b010203':           3
		'c800030c010203':         3
		'c9000000030d010203':     3
	}
	for h, want_len in cases {
		mut u := unpacker(h)
		e := u.unpack_ext()!
		assert e.data.len == want_len, h
		assert u.done(), h
	}
	mut u := unpacker('c7030b010203')
	e := u.unpack_ext()!
	assert e.type_id == 11
	assert e.data == [u8(1), 2, 3]
}

fn test_unpack_timestamps() {
	// timestamp 32, 64 and 96, from the msgpack-test-suite dataset
	mut u := unpacker('d6ff5a4af6a5' + 'd7ffa1dcd7c85a4af6a5' + 'c70cff3b9ac9fffffffffffffffffe')
	t32 := u.unpack_timestamp()!
	assert t32.seconds == 1514862245 && t32.nanoseconds == 0
	t64 := u.unpack_timestamp()!
	assert t64.seconds == 1514862245 && t64.nanoseconds == 678901234
	t96 := u.unpack_timestamp()!
	assert t96.seconds == -2 && t96.nanoseconds == 999999999
	assert u.done()

	mut tu := unpacker('d7ffa1dcd7c85a4af6a5')
	t := tu.unpack_time()!
	assert t.unix() == 1514862245
	assert t.nanosecond == 678901234
}

fn test_unpack_timestamp_rejects_invalid_payloads() {
	// nanoseconds above 999999999
	mut u := unpacker('c70cff3b9aca00' + '0000000000000000')
	u.unpack_timestamp() or {
		assert err is msgpack.MalformedError
		assert u.pos() == 0
		return
	}
	assert false
}

fn test_unpack_timestamp_rejects_other_ext_types() {
	mut u := unpacker('d60130313233')
	u.unpack_timestamp() or {
		assert err is msgpack.TypeMismatchError
		assert u.pos() == 0
		return
	}
	assert false
}

fn test_never_used_byte_is_malformed() {
	u := unpacker('c1')
	if _ := u.peek_kind() {
		assert false
	} else {
		assert err is msgpack.MalformedError
	}
	mut s := unpacker('91c1')
	if _ := s.skip_value() {
		assert false
	} else {
		assert err is msgpack.MalformedError
	}
}

fn test_peek_kind() {
	cases := {
		'c0': msgpack.Kind.nil_val
		'c3': .bool_val
		'05': .uint_val
		'cd': .uint_val
		'f0': .int_val
		'd3': .int_val
		'ca': .f32_val
		'cb': .f64_val
		'a1': .str_val
		'c4': .bin_val
		'91': .array_val
		'81': .map_val
		'd6': .ext_val
	}
	for h, kind in cases {
		u := unpacker(h)
		assert u.peek_kind()! == kind, h
	}
}

// A value whose encoding is cut short anywhere must fail with an error,
// never panic and never read past the input.
fn test_truncated_input_returns_errors() {
	full := [
		'cd0100',
		'ce00010000',
		'cf0000000100000000',
		'd18000',
		'd3ffffffffffffffff',
		'ca4048f5c3',
		'cb40091eb851eb851f',
		'd903616263',
		'da0003616263',
		'db00000003616263',
		'c403010203',
		'c50003010203',
		'c600000003010203',
		'dc0001c0',
		'dd00000001c0',
		'de0001c0c0',
		'df00000001c0c0',
		'd6ff5a4af6a5',
		'c7030b010203',
		'c9000000030d010203',
		'92a16193c0c3c2',
	]
	for h in full {
		data := hex.decode(h)!
		for cut in 0 .. data.len {
			mut u := msgpack.new_unpacker(data[..cut])
			if _ := u.skip_value() {
				assert false, 'skip_value accepted ${h} cut at ${cut}'
			}
			assert u.pos() == 0
		}
		mut u := msgpack.new_unpacker(data)
		u.skip_value()!
		assert u.done(), h
	}
}

fn test_declared_lengths_larger_than_input_are_rejected() {
	for h in ['dbffffffff', 'c6ffffffff', 'c9ffffffff01', 'ddffffffff', 'dfffffffff'] {
		mut u := unpacker(h)
		if _ := u.skip_value() {
			assert false, h
		}
	}
	mut a := unpacker('ddffffffff')
	a.unpack_array_header() or {
		assert err is msgpack.UnexpectedEofError
		return
	}
	assert false
}

fn test_skip_value_nested() {
	// [1, {"a": [nil, true]}, "xyz", bin, ext]
	mut u := unpacker('95' + '01' + '81a16192c0c3' + 'a378797a' + 'c40100' + 'd40102' + 'c0')
	u.skip_value()!
	assert u.pos() == 18
	u.unpack_nil()!
	assert u.done()
}
