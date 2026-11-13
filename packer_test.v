module main

import msgpack
import time

fn packed(f fn (mut p msgpack.Packer) !) string {
	mut p := msgpack.new_packer()
	f(mut p) or { panic(err) }
	return p.bytes().hex()
}

fn test_pack_integers_use_the_smallest_format() {
	cases := {
		i64(0):      '00'
		127:         '7f'
		128:         'cc80'
		255:         'ccff'
		256:         'cd0100'
		65535:       'cdffff'
		65536:       'ce00010000'
		4294967295:  'ceffffffff'
		4294967296:  'cf0000000100000000'
		max_i64:     'cf7fffffffffffffff'
		-1:          'ff'
		-32:         'e0'
		-33:         'd0df'
		-128:        'd080'
		-129:        'd1ff7f'
		-32768:      'd18000'
		-32769:      'd2ffff7fff'
		-2147483648: 'd280000000'
		-2147483649: 'd3ffffffff7fffffff'
		min_i64:     'd38000000000000000'
	}
	for v, want in cases {
		mut p := msgpack.new_packer()
		p.pack_int(v)
		assert p.bytes().hex() == want, v.str()
		mut u := msgpack.new_unpacker(p.bytes())
		assert u.unpack_int()! == v
	}
	mut p := msgpack.new_packer()
	p.pack_uint(max_u64)
	assert p.bytes().hex() == 'cfffffffffffffffff'
}

fn test_pack_nil_bool_floats() {
	assert packed(fn (mut p msgpack.Packer) ! {
		p.pack_nil()
		p.pack_bool(false)
		p.pack_bool(true)
		p.pack_f32(3.14)
		p.pack_f64(3.14)
	}) == 'c0c2c3' + 'ca4048f5c3' + 'cb40091eb851eb851f'
}

fn test_pack_str_formats() {
	for n, prefix in {
		0:     'a0'
		31:    'bf'
		32:    'd920'
		255:   'd9ff'
		256:   'da0100'
		65535: 'daffff'
		65536: 'db00010000'
	} {
		s := 'x'.repeat(n)
		mut p := msgpack.new_packer()
		p.pack_str(s)!
		assert p.bytes().hex().starts_with(prefix), n.str()
		assert p.bytes().len == prefix.len / 2 + n
		mut u := msgpack.new_unpacker(p.bytes())
		assert u.unpack_str()! == s
	}
}

fn test_pack_bin_formats() {
	for n, prefix in {
		0:     'c400'
		255:   'c4ff'
		256:   'c50100'
		65536: 'c600010000'
	} {
		data := []u8{len: n, init: u8(index)}
		mut p := msgpack.new_packer()
		p.pack_bin(data)!
		assert p.bytes().hex().starts_with(prefix), n.str()
		mut u := msgpack.new_unpacker(p.bytes())
		assert u.unpack_bin()! == data
	}
}

fn test_pack_container_headers() {
	for n, want in {
		u32(0): '90'
		15:     '9f'
		16:     'dc0010'
		65535:  'dcffff'
		65536:  'dd00010000'
	} {
		mut p := msgpack.new_packer()
		p.pack_array_header(n)
		assert p.bytes().hex() == want
	}
	for n, want in {
		u32(0): '80'
		15:     '8f'
		16:     'de0010'
		65536:  'df00010000'
	} {
		mut p := msgpack.new_packer()
		p.pack_map_header(n)
		assert p.bytes().hex() == want
	}
}

fn test_pack_ext_formats() {
	for n, prefix in {
		1:   'd405'
		2:   'd505'
		4:   'd605'
		8:   'd705'
		16:  'd805'
		0:   'c70005'
		3:   'c70305'
		17:  'c71105'
		256: 'c8010005'
	} {
		data := []u8{len: n, init: u8(index)}
		mut p := msgpack.new_packer()
		p.pack_ext(5, data)!
		assert p.bytes().hex().starts_with(prefix), n.str()
		mut u := msgpack.new_unpacker(p.bytes())
		e := u.unpack_ext()!
		assert e.type_id == 5
		assert e.data == data
	}
}

fn test_pack_timestamp_uses_the_smallest_format() {
	cases := {
		'd6ff00000000':                   msgpack.Timestamp{}
		'd6ffffffffff':                   msgpack.Timestamp{
			seconds: 4294967295
		}
		'd7ff0000000100000000':           msgpack.Timestamp{
			seconds: 4294967296
		}
		'd7ffee6b27fc7fffffff':           msgpack.Timestamp{
			seconds:     2147483647
			nanoseconds: 999999999
		}
		'c70cff000000000000000400000000': msgpack.Timestamp{
			seconds: 17179869184
		}
		'c70cff3b9ac9fffffffffffffffffe': msgpack.Timestamp{
			seconds:     -2
			nanoseconds: 999999999
		}
	}
	for want, ts in cases {
		mut p := msgpack.new_packer()
		p.pack_timestamp(ts)!
		assert p.bytes().hex() == want
		mut u := msgpack.new_unpacker(p.bytes())
		assert u.unpack_timestamp()! == ts
	}
	mut p := msgpack.new_packer()
	if _ := p.pack_timestamp(msgpack.Timestamp{ nanoseconds: 1_000_000_000 }) {
		assert false
	}
}

fn test_pack_time_keeps_nanoseconds() {
	t := time.unix_nanosecond(1514862245, 678901234)
	mut p := msgpack.new_packer()
	p.pack_time(t)!
	assert p.bytes().hex() == 'd7ffa1dcd7c85a4af6a5'
	mut u := msgpack.new_unpacker(p.bytes())
	back := u.unpack_time()!
	assert back.unix() == t.unix()
	assert back.nanosecond == t.nanosecond
	// times before 1970 use the 96-bit format
	mut old := msgpack.new_packer()
	old.pack_time(time.unix(-100))!
	mut ou := msgpack.new_unpacker(old.bytes())
	assert ou.unpack_time()!.unix() == -100
}

fn test_pack_time_rejects_invalid_nanoseconds() {
	mut p := msgpack.new_packer()
	if _ := p.pack_time(time.Time{
		nanosecond: 1_000_000_000
	}) {
		assert false
	}
}

fn test_reset_reuses_the_buffer() {
	mut p := msgpack.new_packer(initial_cap: 16)
	p.pack_str('hello')!
	p.reset()
	p.pack_int(1)
	assert p.bytes() == [u8(1)]
}

fn test_packing_bytes_of_the_buffer_itself() {
	mut p := msgpack.new_packer(initial_cap: 4)
	p.pack_str('abc')!
	// the source is inside the buffer, which grows during the call
	p.pack_bin(p.bytes())!
	assert p.bytes().hex() == 'a3616263' + 'c404a3616263'
	p.pack_str(p.bytes()[1..4].bytestr())!
	p.pack_ext(7, p.bytes()[1..4])!
	assert p.bytes().hex().ends_with('a3616263' + 'c70307616263')
}
