module main

import msgpack
import encoding.hex
import time

struct Record {
	name    string
	values  []i64
	payload []u8
	ratio   f64
	missing ?int
	created time.Time
}

enum Shade {
	red  = 3
	blue = 7
}

fn test_generic_struct_and_nested_containers() {
	value := Record{
		name:    'été'.repeat(20)
		values:  [i64(-129), 2147483648, 9223372036854775807]
		payload: [u8(0), 128, 255]
		ratio:   1.5
		missing: none
		created: time.unix_nanosecond(-1, 999999999)
	}
	back := msgpack.decode[Record](msgpack.encode(value)!)!
	assert back.name == value.name
	assert back.values == value.values
	assert back.payload == value.payload
	assert back.ratio == value.ratio
	assert back.missing == none
	assert back.created.unix() == value.created.unix()
	assert back.created.nanosecond == value.created.nanosecond
	maps := {
		'one': [i64(1), 2]
		'two': [i64(-1), 3]
	}
	assert msgpack.decode[map[string][]i64](msgpack.encode(maps)!)! == maps
	fixed := [i16(-129), 256]!
	assert msgpack.decode[[2]i16](msgpack.encode(fixed)!)! == fixed
}

fn test_generic_numeric_widths_and_options() {
	assert msgpack.encode(i64(-129))!.hex() == 'd1ff7f'
	assert msgpack.encode(u64(18446744073709551615))!.hex() == 'cfffffffffffffffff'
	assert msgpack.decode[u64](hex.decode('cfffffffffffffffff')!)! == u64(18446744073709551615)
	assert msgpack.decode[i64](hex.decode('d38000000000000000')!)! == i64(-9223372036854775807) - 1
	assert msgpack.decode[f64](msgpack.encode(u64(1) << 54)!)! == 18014398509481984.0
	if _ := msgpack.decode[f32](msgpack.encode(16777217)!) {
		assert false
	} else {
		assert err is msgpack.IntRangeError
	}
	assert msgpack.decode[Shade](msgpack.encode(Shade.blue)!)! == Shade.blue
	assert msgpack.decode[Shade](msgpack.encode(Shade.blue, enum_as_string: true)!)! == Shade.blue
}

fn test_generic_value_and_json() {
	assert msgpack.decode[string](msgpack.encode([u8(97), 98])!)! == 'ab'
	assert msgpack.decode[[]u8](msgpack.encode('ab')!)! == [u8(97), 98]
	assert msgpack.decode_to_json(msgpack.encode('a"b\n')!)! == '"a\\"b\\n"'
	assert msgpack.decode_to_json(msgpack.encode([u8(0), 255])!)! == '"AP8="'
	value := msgpack.decode[msgpack.Value](msgpack.encode(u64(18446744073709551615))!)!
	assert value.as_uint()? == u64(18446744073709551615)
	if _ := msgpack.decode[int]([u8(0xc0)]) {
		assert false
	} else {
		assert err is msgpack.TypeMismatchError
	}
}
