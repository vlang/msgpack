module main

import msgpack
import encoding.hex
import encoding.binary
import math
import os
import strconv

struct Tokens {
	a []string
mut:
	pos int
}

fn (mut t Tokens) next() !string {
	if t.pos >= t.a.len {
		return error('missing transport token')
	}
	s := t.a[t.pos]
	t.pos++
	return s
}

fn unhex(s string) ![]u8 {
	if s == '-' {
		return []u8{}
	}
	return hex.decode(s)!
}

fn pack(mut t Tokens, mut p msgpack.Packer) ! {
	kind := t.next()!
	match kind {
		'n' { p.pack_nil() }
		'b' { p.pack_bool(t.next()! == '1') }
		'i' {
			s := t.next()!
			if s.starts_with('-') {
				p.pack_int(strconv.parse_int(s, 10, 64)!)
			} else {
				p.pack_uint(strconv.parse_uint(s, 10, 64)!)
			}
		}
		'f' {
			b := unhex(t.next()!)!
			p.pack_f32(math.f32_from_bits(binary.big_endian_u32(b)))
		}
		'd' {
			b := unhex(t.next()!)!
			p.pack_f64(math.f64_from_bits(binary.big_endian_u64(b)))
		}
		's' {
			b := unhex(t.next()!)!
			p.pack_str(b.bytestr())!
		}
		'x' {
			b := unhex(t.next()!)!
			p.pack_bin(b)!
		}
		'a', 'm' {
			n := t.next()!.int()
			if kind == 'a' { p.pack_array_header(u32(n)) } else { p.pack_map_header(u32(n)) }
			count := if kind == 'm' { n * 2 } else { n }
			for _ in 0 .. count {
				pack(mut t, mut p)!
			}
		}
		'e' {
			tag := i8(t.next()!.int())
			b := unhex(t.next()!)!
			if tag == -1 {
				ts := match b.len {
					4 { msgpack.Timestamp{ seconds: i64(binary.big_endian_u32(b)) } }
					8 {
						n := binary.big_endian_u64(b)
						msgpack.Timestamp{ seconds: i64(n & 0x3ffffffff), nanoseconds: u32(n >> 34) }
					}
					12 {
						msgpack.Timestamp{ seconds: i64(binary.big_endian_u64(b[4..])), nanoseconds: binary.big_endian_u32(b) }
					}
					else { return error('timestamp length') }
				}
				p.pack_timestamp(ts)!
			} else {
				p.pack_ext(tag, b)!
			}
		}
		else { return error('unknown transport token') }
	}
}

fn hx(b []u8) string {
	return if b.len == 0 { '-' } else { b.hex() }
}

fn unpack(mut u msgpack.Unpacker, mut out []string) ! {
	k := u.peek_kind()!
	match k {
		.nil_val {
			u.unpack_nil()!
			out << 'n'
		}
		.bool_val {
			v := u.unpack_bool()!
			out << ['b', if v { '1' } else { '0' }]
		}
		.uint_val {
			v := u.unpack_uint()!
			out << ['i', v.str()]
		}
		.int_val {
			v := u.unpack_int()!
			out << ['i', v.str()]
		}
		.f32_val {
			v := u.unpack_f32()!
			out << ['f', '${math.f32_bits(v):08x}']
		}
		.f64_val {
			v := u.unpack_f64()!
			out << ['d', '${math.f64_bits(v):016x}']
		}
		.str_val {
			v := u.unpack_str()!
			out << ['s', hx(v.bytes())]
		}
		.bin_val {
			v := u.unpack_bin()!
			out << ['x', hx(v)]
		}
		.array_val {
			n := u.unpack_array_header()!
			out << ['a', n.str()]
			for _ in 0 .. n {
				unpack(mut u, mut out)!
			}
		}
		.map_val {
			n := u.unpack_map_header()!
			out << ['m', n.str()]
			for _ in 0 .. n * 2 {
				unpack(mut u, mut out)!
			}
		}
		.ext_val {
			start := u.pos()
			v := u.unpack_ext()!
			if v.type_id == -1 {
				mut check := msgpack.new_unpacker(u.data[start..u.pos()])
				ts := check.unpack_timestamp()!
				mut p := msgpack.new_packer()
				p.pack_timestamp(ts)!
				mut t := msgpack.new_unpacker(p.bytes())
				e := t.unpack_ext()!
				out << ['e', '-1', hx(e.data)]
			} else {
				out << ['e', v.type_id.str(), hx(v.data)]
			}
		}
	}
}

fn value_tokens(v msgpack.Value, mut out []string) ! {
	match v {
		msgpack.Nil { out << 'n' }
		bool { out << ['b', if v { '1' } else { '0' }] }
		i64 { out << ['i', v.str()] }
		u64 { out << ['i', v.str()] }
		f32 { out << ['f', '${math.f32_bits(v):08x}'] }
		f64 { out << ['d', '${math.f64_bits(v):016x}'] }
		string { out << ['s', hx(v.bytes())] }
		[]u8 { out << ['x', hx(v)] }
		[]msgpack.Value {
			out << ['a', v.len.str()]
			for x in v {
				value_tokens(x, mut out)!
			}
		}
		msgpack.Map {
			out << ['m', v.entries.len.str()]
			for e in v.entries {
				value_tokens(e.key, mut out)!
				value_tokens(e.value, mut out)!
			}
		}
		msgpack.Ext { out << ['e', v.type_id.str(), hx(v.data)] }
		msgpack.Timestamp {
			mut p := msgpack.new_packer()
			p.pack_timestamp(v)!
			mut u := msgpack.new_unpacker(p.bytes())
			e := u.unpack_ext()!
			out << ['e', '-1', hx(e.data)]
		}
	}
}

fn process(line string) !string {
	a := line.fields()
	if a.len == 0 {
		return error('empty request')
	}
	if a[0] == 'E' {
		mut t := Tokens{ a: a[1..] }
		mut p := msgpack.new_packer()
		pack(mut t, mut p)!
		if t.pos != t.a.len {
			return error('extra transport tokens')
		}
		if '--generic' in os.args {
			value := msgpack.decode[msgpack.Value](p.bytes())!
			encoded := msgpack.encode[msgpack.Value](value)!
			return 'H ' + encoded.hex()
		}
		return 'H ' + p.bytes().hex()
	}
	if a[0] == 'D' {
		b := hex.decode(a[1])!
		if '--generic' in os.args {
			value := msgpack.decode[msgpack.Value](b)!
			mut out := []string{}
			value_tokens(value, mut out)!
			return 'V ' + out.join(' ')
		}
		mut u := msgpack.new_unpacker(b)
		mut out := []string{}
		unpack(mut u, mut out)!
		if !u.done() {
			return error('trailing bytes')
		}
		return 'V ' + out.join(' ')
	}
	return error('unknown operation')
}

fn main() {
	for {
		line := os.get_raw_line()
		if line.len == 0 {
			break
		}
		result := process(line) or { 'X ' + err.msg().replace('\n', ' ') }
		println(result)
	}
}
