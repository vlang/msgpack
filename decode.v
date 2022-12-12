module msgpack

import time
import encoding.hex
import encoding.binary

const (
	msg_bad_desc = 'unrecognized descriptor byte'
)

struct Decoder {
	config Config = default_config()
mut:
	pos    int
	buffer []u8
	bd     u8
}

pub fn new_decoder() Decoder {
	return Decoder{}
}

pub fn decode[T](src []u8) !T {
	return T{}
}

pub fn (mut d Decoder) decode_from_string(data string) ! {
	d.decode(hex.decode(data) or { return error('error decoding hex string') })!
}

// TODO: proper decoding into data structures
// for now just get decoding of all types working.
pub fn (mut d Decoder) decode(data []u8) ! {
	d.buffer = data
	for d.pos < d.buffer.len {
		d.next()
		d.decode_()!
	}
}

fn (mut d Decoder) decode_() ! {
	match d.bd {
		mp_nil {
			// n.v = .nil_
			// d.bdRead = false
			println('nil')
		}
		mp_false {
			// n.v = valueTypeBool
			// n.b = false
			println('false')
		}
		mp_true {
			// n.v = valueTypeBool
			// n.b = true
			println('true')
		}
		mp_f32 {
			// n.v = valueTypeFloat
			// n.f = float64(math.Float32frombits(binary.big_endian_u32(d.d.decRd.readn4())))
			println('f32')
		}
		mp_f64 {
			// n.v = valueTypeFloat
			// n.f = math.Float64frombits(binary.big_endian_u64(d.d.decRd.readn8()))
			println('f64')
		}
		mp_u8 {
			// n.v = valueTypeUint
			// n.u = u64(d.d.decRd.readn1())
			println('u8')
		}
		mp_u16 {
			// n.v = valueTypeUint
			// n.u = u64(binary.big_endian_u16(d.d.decRd.readn2()))
			println('u16')
		}
		mp_u32 {
			// n.v = valueTypeUint
			// n.u = u64(binary.big_endian_u32(d.d.decRd.readn4()))
			println('u32')
		}
		mp_u64 {
			// n.v = valueTypeUint
			// n.u = u64(binary.big_endian_u64(d.d.decRd.readn8()))
			println('u64')
		}
		mp_i8 {
			// n.v = valueTypeInt
			// n.i = i64(int8(d.d.decRd.readn1()))
			println('i8')
		}
		mp_i16 {
			// n.v = valueTypeInt
			// n.i = i64(int16(binary.big_endian_u16(d.d.decRd.readn2())))
			println('i16')
		}
		mp_i32 {
			// n.v = valueTypeInt
			// n.i = i64(int32(binary.big_endian_u32(d.d.decRd.readn4())))
			i := i64(int(binary.big_endian_u32(d.read_n(4))))
			// d.next()
			println('int: ${i}')
		}
		mp_i64 {
			// n.v = valueTypeInt
			// n.i = i64(i64(binary.big_endian_u64(d.d.decRd.readn8())))
			println('i64')
		}
		else {
			// println('else: $d.bd')
			if d.bd in [mp_bin_8, mp_bin_16, mp_bin_32] {
				println('bin')
			} else if d.bd in [mp_str_8, mp_str_16, mp_str_32]
				|| (d.bd >= mp_fix_str_min && d.bd <= mp_fix_str_max) {
				// println('string')
				d.decode_string()!
			} else if d.bd in [mp_array_16, mp_array_32]
				|| (d.bd >= mp_fix_array_min && d.bd <= mp_fix_array_max) {
				println('array')
			} else if d.bd in [mp_map_16, mp_map_32]
				|| (d.bd >= mp_fix_map_min && d.bd <= mp_fix_map_max) {
				d.decode_map()!
			} else if (d.bd >= mp_fix_ext_1 && d.bd <= mp_fix_ext_16)
				|| (d.bd >= mp_ext_8 && d.bd <= mp_ext_32) {
				d.decode_ext()!
			}
		}
	}
	// default:
	// 	switch {
	// 		bd >= mpPosFixNumMin && bd <= mpPosFixNumMax:
	// 		// positive fixnum (always signed)
	// 		n.v = valueTypeInt
	// 		n.i = i64(int8(bd))
	// 		bd >= mpNegFixNumMin && bd <= mpNegFixNumMax:
	// 		// negative fixnum
	// 		n.v = valueTypeInt
	// 		n.i = i64(int8(bd))
	// 		bd == mp_str_8, bd == mp_str_16, bd == mp_str_32, bd >= mp_fix_str_min && bd <= mp_fix_str_max:
	// 		d.d.fauxUnionReadRawBytes(d.h.WriteExt)
	// 		// if d.h.WriteExt || d.h.RawToString {
	// 		// 	n.v = .string_
	// 		// 	n.s = d.d.string_ZC(d.DecodeStringAsBytes())
	// 		// } else {
	// 		// 	n.v = .bytes
	// 		// 	n.l = d.DecodeBytes([]byte{})
	// 		// }
	// 		bd == mp_bin_8, bd == mp_bin_16, bd == mp_bin_32:
	// 		d.d.fauxUnionReadRawBytes(false)
	// 		bd == mp_array_16, bd == mp_array_32, bd >= mp_fix_array_min && bd <= mp_fix_array_max:
	// 		n.v = .array
	// 		decodeFurther = true
	// 		bd == mp_map_16, bd == mp_map_32, bd >= mp_fix_map_min && bd <= mp_fix_map_max:
	// 		n.v = .map_
	// 		decodeFurther = true
	// 		bd >= mp_fix_ext_1 && bd <= mp_fix_ext_16, bd >= mp_ext_8 && bd <= mp_ext_32:
	// 		n.v = valueTypeExt
	// 		clen := d.readExtLen()
	// 		n.u = u64(d.d.decRd.readn1())
	// 		if n.u == u64(mpTimeExtTagU) {
	// 			n.v = valueTypeTime
	// 			n.t = d.decodeTime(clen)
	// 		} else if d.d.bytes {
	// 			n.l = d.d.decRd.rb.readx(uint(clen))
	// 		} else {
	// 			n.l = decByteSlice(d.d.r(), clen, d.d.h.MaxInitLen, d.d.b[:])
	// 		}
	// 	default:
	// 		d.d.errorf("cannot infer value: %s: Ox%x/%d/%s", msg_bad_desc, bd, bd, mpdesc(bd))
	// 	}
}

fn (mut d Decoder) decode_ext() ! {
	// n.v = valueTypeExt
	clen := d.read_ext_len()!
	println('decode_ext - container len: ${clen}')
	if d.bd == mp_time_ext_type {
		// n.v = valueTypeTime
		t := d.decode_time(clen)
		println('time: ${t}')
	}
	// TODO: d.d.bytes?
	// else if d.d.bytes {
	// n.l = d.d.decRd.rb.readx(uint(clen))
	// }
	else {
		// n.l = decByteSlice(d.d.r(), clen, d.d.h.MaxInitLen, d.d.b[:])
	}
}

fn (mut d Decoder) decode_string() ! {
	ct := match d.config.write_ext {
		true {
			match d.config.string_raw {
				true { container_bin }
				else { container_str }
			}
		}
		else {
			container_raw_legacy
		}
	}
	len := d.read_container_len(ct)!
	x := d.read_n(len)
	println('string: ${x.bytestr()} - len: ${len}')
	d.decode_()!
}

fn (mut d Decoder) decode_map() ! {
	// containerLen := d.arrayStart(d.d.ReadArrayStart())
	// if containerLen == 0 {
	// 	d.arrayEnd()
	// 	return
	// }
	d.next()
	container_len := d.read_map_start()!
	println('map container_len: ${container_len}')
	d.decode_()!
}

fn (mut d Decoder) container_type() ValueType {
	// if !d.bdRead {
	// 	d.readNextBd()
	// }
	d.next()
	bd := d.bd
	if bd == mp_nil {
		// d.bdRead = false
		return .nil_
	} else if bd == mp_bin_8 || bd == mp_bin_16 || bd == mp_bin_32 {
		return .bytes
	} else if bd == mp_str_8 || bd == mp_str_16 || bd == mp_str_32
		|| (bd >= mp_fix_str_min && bd <= mp_fix_str_max) {
		if d.config.write_ext || d.config.string_raw { // UTF-8 string (new spec)
			return .string_
		}
		return .bytes // raw (old spec)
	} else if bd == mp_array_16 || bd == mp_array_32
		|| (bd >= mp_fix_array_min && bd <= mp_fix_array_max) {
		return .array
	} else if bd == mp_map_16 || bd == mp_map_32 || (bd >= mp_fix_map_min && bd <= mp_fix_map_max) {
		return .map_
	}
	return .unset
}

fn (mut d Decoder) read_container_len(ct ContainerType) !int {
	bd := d.bd
	if bd == ct.b8 {
		return int(d.read_1())
	} else if bd == ct.b16 {
		return int(binary.big_endian_u16(d.read_n(2)))
	} else if bd == ct.b32 {
		return int(binary.big_endian_u32(d.read_n(4)))
	} else if (ct.b_fix_min & bd) == ct.b_fix_min {
		return int(ct.b_fix_min ^ bd)
	} else {
		// return('cannot read container length: %s: hex: %x, decimal: %d', msg_bad_desc, bd, bd)
		return error('cannot read container length: ${msgpack.msg_bad_desc}: hex: ${bd.hex()}, decimal: ${bd}')
	}
	// d.bdRead = false
	// return
}

fn (mut d Decoder) read_map_start() !int {
	// if d.advanceNil() {
	if d.bd == mp_nil {
		return container_len_nil
	}
	return d.read_container_len(container_map)
}

fn (mut d Decoder) read_array_start() !int {
	// if d.advanceNil() {
	if d.bd == mp_nil {
		return container_len_nil
	}
	return d.read_container_len(container_array)
}

fn (mut d Decoder) read_ext_len() !int {
	match d.bd {
		mp_fix_ext_1 {
			d.next()
			return 1
		}
		mp_fix_ext_2 {
			d.next()
			return 2
		}
		mp_fix_ext_4 {
			d.next()
			return 4
		}
		mp_fix_ext_8 {
			d.next()
			return 8
		}
		mp_fix_ext_16 {
			d.next()
			return 16
		}
		mp_ext_8 {
			return int(d.read_1())
		}
		mp_ext_16 {
			return int(binary.big_endian_u16(d.read_n(2)))
		}
		mp_ext_32 {
			return int(binary.big_endian_u32(d.read_n(4)))
		}
		else {
			return error('decoding ext bytes: found unexpected byte: ${d.bd.hex()}')
		}
	}
}

// func (d *msgpackDecDriver) DecodeTime() (t time.Time) {
// 	// decode time from string bytes or ext
// 	if d.advanceNil() {
// 		return
// 	}
// 	bd := d.bd
// 	var clen int
// 	if bd == mp_bin_8 || bd == mp_bin_16 || bd == mp_bin_32 {
// 		clen = d.read_container_len(msgpackContainerBin) // binary
// 	} else if bd == mp_str_8 || bd == mp_str_16 || bd == mp_str_32 ||
// 		(bd >= mp_fix_str_min && bd <= mp_fix_str_max) {
// 		clen = d.read_container_len(msgpackContainerStr) // string/raw
// 	} else {
// 		// expect to see mp_fix_ext_4,-1 OR mp_fix_ext_8,-1 OR mp_ext_8,12,-1
// 		d.bdRead = false
// 		b2 := d.d.decRd.readn1()
// 		if d.bd == mp_fix_ext_4 && b2 == mpTimeExtTagU {
// 			clen = 4
// 		} else if d.bd == mp_fix_ext_8 && b2 == mpTimeExtTagU {
// 			clen = 8
// 		} else if d.bd == mp_ext_8 && b2 == 12 && d.d.decRd.readn1() == mpTimeExtTagU {
// 			clen = 12
// 		} else {
// 			d.d.errorf("invalid stream for decoding time as extension: got 0x%x, 0x%x", d.bd, b2)
// 		}
// 	}
// 	return d.decodeTime(clen)
// }

// fn (mut d Decoder) decode_ext(rv interface{}, basetype reflect.Type, xtag uint64, ext Ext) {
// 	if xtag > 0xff {
// 		d.d.errorf("ext: tag must be <= 0xff; got: %v", xtag)
// 	}
// 	if d.advanceNil() {
// 		return
// 	}
// 	xbs, realxtag1, zerocopy := d.decodeExtV(ext != nil, uint8(xtag))
// 	realxtag := u64(realxtag1)
// 	if ext == nil {
// 		re := rv.(*RawExt)
// 		re.Tag = realxtag
// 		re.setData(xbs, zerocopy)
// 	} else if ext == SelfExt {
// 		d.d.sideDecode(rv, basetype, xbs)
// 	} else {
// 		ext.ReadExt(rv, xbs)
// 	}
// }

fn (mut d Decoder) decode_time(clen int) time.Time {
	// d.bdRead = false
	match clen {
		4 {
			return time.unix(i64(binary.big_endian_u32(d.read_n(4))))
		}
		else {
			panic('unsupported currently')
		}
	}
	// match clen {
	// 	4 {
	// 		// return time.unix(i64(binary.big_endian_u32(d.d.decRd.readn4())), 0).utc()
	// 		return time.unix(i64(binary.big_endian_u32(d.read4())), 0).utc()
	// 	}
	// 	8 {
	// 		// tv := binary.big_endian_u64(d.d.decRd.readn8())
	// 		// return time.Unix(i64(tv&0x00000003ffffffff), i64(tv>>34)).utc()
	// 		tv := binary.big_endian_u64(d.d.decRd.readn8())
	// 		return time.unix(i64(tv&0x00000003ffffffff), i64(tv>>34)).utc()
	// 	}
	// 	12 {
	// 		nsec := binary.big_endian_u32(d.readn4())
	// 		sec := binary.big_endian_u64(d.readn8())
	// 		return time.unix(i64(sec), i64(nsec)).utc()
	// 	}
	// 	else {
	// 		// d.error("invalid length of bytes for decoding time - expecting 4 or 8 or 12, got $clen")
	// 	}
	// }
}

pub fn (mut d Decoder) next() {
	d.bd = d.buffer[d.pos]
	d.pos++
}

fn (mut d Decoder) read_1() u8 {
	d.next()
	return d.buffer[d.pos]
}

fn (mut d Decoder) read_n(len int) []u8 {
	b := d.buffer[d.pos..d.pos + len]
	d.pos += len - 1
	d.next()
	return b
}
