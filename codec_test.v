module main

import encoding.hex
import msgpack
import time

enum Color {
	red
	green = 5
	blue
}

@[flag]
enum Perm {
	read
	write
	exec
}

type UserId = u32

struct Empty {}

struct Envelope {
	kind    string
	payload msgpack.Value
}

struct Point {
	x f64
	y f64
}

struct Address {
	city string
	zip  string
}

struct User {
	id       UserId
	name     string
	email    ?string
	age      ?int
	scores   []int
	tags     map[string]string
	home     Address
	places   []Point
	color    Color
	perms    Perm
	avatar   []u8
	created  time.Time
	nickname string @[msgpack.Key: 'nick']
}

fn sample_user() User {
	return User{
		id:       42
		name:     'Ada Lovelace, the first programmer of a machine'
		email:    'ada@example.com'
		scores:   []int{len: 20, init: index * 1000}
		tags:     {
			'lang': 'en'
			'role': 'admin'
		}
		home:     Address{'London', 'W1'}
		places:   [Point{1.5, -2.25}, Point{0, 1e100}]
		color:    .blue
		perms:    .read | .exec
		avatar:   []u8{len: 300, init: u8(index)}
		created:  time.unix_nanosecond(1_700_000_000, 123_456_789)
		nickname: 'countess'
	}
}

fn test_struct_round_trip() {
	u := sample_user()
	back := msgpack.decode[User](msgpack.encode(u)!)!
	assert back.id == u.id
	assert back.name == u.name
	assert back.email or { '' } == 'ada@example.com'
	assert back.age == none
	assert back.scores == u.scores
	assert back.tags == u.tags
	assert back.home == u.home
	assert back.places == u.places
	assert back.color == .blue
	assert back.perms == u.perms
	assert back.avatar == u.avatar
	assert back.created.unix() == u.created.unix()
	assert back.created.nanosecond == 123_456_789
	assert back.nickname == 'countess'
}

fn test_primitives_round_trip() {
	assert msgpack.decode[string](msgpack.encode('x'.repeat(40))!)! == 'x'.repeat(40)
	assert msgpack.decode[string](msgpack.encode('é日本'.repeat(30000))!)! == 'é日本'.repeat(30000)
	assert msgpack.decode[[]u8](msgpack.encode([u8(1), 2, 3])!)! == [u8(1), 2, 3]
	assert msgpack.decode[i8](msgpack.encode(i8(-128))!)! == -128
	assert msgpack.decode[u64](msgpack.encode(max_u64)!)! == max_u64
	assert msgpack.decode[i64](msgpack.encode(min_i64)!)! == min_i64
	assert msgpack.decode[f32](msgpack.encode(f32(1.25))!)! == 1.25
	assert msgpack.decode[bool](msgpack.encode(true)!)!
	assert msgpack.decode[UserId](msgpack.encode(UserId(7))!)! == 7
}

fn test_platform_width_unsigned_round_trip() {
	// uint is as wide as a pointer, so its largest value depends on the target.
	largest := if sizeof(uint) == 8 { uint(max_u64) } else { uint(max_u32) }
	assert msgpack.decode[uint](msgpack.encode(largest)!)! == largest
	assert msgpack.decode[uint](msgpack.encode(uint(0))!)! == 0
	if sizeof(uint) == 4 {
		msgpack.decode[uint](msgpack.encode(u64(max_u32) + 1)!) or { return }
		assert false, 'a value above the range of uint was accepted'
	}
	msgpack.decode[uint](msgpack.encode(-1)!) or { return }
	assert false, 'a negative value was decoded into uint'
}

fn test_containers_round_trip() {
	nested := [[1, 2], [3], []int{}]
	assert msgpack.decode[[][]int](msgpack.encode(nested)!)! == nested
	long := []int{len: 70000, init: index - 35000}
	assert msgpack.decode[[]int](msgpack.encode(long)!)! == long
	strs := ['a', 'b'.repeat(33), '']
	assert msgpack.decode[[]string](msgpack.encode(strs)!)! == strs
	m := {
		'one': 1
		'two': 2
	}
	assert msgpack.decode[map[string]int](msgpack.encode(m)!)! == m
	im := {
		u8(1):   [f64(0.5)]
		u8(255): []f64{}
	}
	assert msgpack.decode[map[u8][]f64](msgpack.encode(im)!)! == im
	fixed := [3]u16{init: u16(index + 60000)}
	assert msgpack.decode[[3]u16](msgpack.encode(fixed)!)! == fixed
}

fn test_encoding_matches_the_spec() {
	assert msgpack.encode(Address{'Paris', '75'})!.hex() == '82a463697479a55061726973a37a6970a23735'
	assert msgpack.encode(Empty{})!.hex() == '80'
	assert msgpack.encode([]int{})!.hex() == '90'
	assert msgpack.encode(map[string]int{})!.hex() == '80'
	assert msgpack.encode(?int(none))!.hex() == 'c0'
	assert msgpack.encode(Color.green)!.hex() == '05'
	assert msgpack.encode(Color.green, enum_as_string: true)!.hex() == 'a5677265656e'
	assert msgpack.encode([2]bool{})!.hex() == '92c2c2'
	// flag enums stay integers: a combination of flags has no name
	assert msgpack.encode(Perm.read | Perm.exec, enum_as_string: true)!.hex() == '05'
}

fn test_time_encoding() {
	// whole minutes and times before 1970 are regular timestamps
	t := time.parse('2024-01-01 12:34:00')!
	assert msgpack.encode(t)!.hex() == 'd6ff' + u32(t.unix()).hex()
	assert msgpack.decode[time.Time](msgpack.encode(time.unix(-100))!)!.unix() == -100
}

fn test_sort_keys() {
	m := {
		'b': 2
		'a': 1
		'c': 3
	}
	assert msgpack.encode(m, sort_keys: true)!.hex() == '83a16101a16202a16303'
}

fn test_decode_accepts_equivalent_formats() {
	// int32-encoded values, as written by some implementations
	assert msgpack.decode[u8](hex.decode('d20000002a')!)! == 42
	// str into []u8 and bin into string
	assert msgpack.decode[[]u8](hex.decode('a3616263')!)! == 'abc'.bytes()
	assert msgpack.decode[string](hex.decode('c403616263')!)! == 'abc'
	// float64 into f32, exact integer into f64
	assert msgpack.decode[f32](hex.decode('cb3ff8000000000000')!)! == 1.5
	assert msgpack.decode[f64](hex.decode('2a')!)! == 42.0
	// enum from its name
	assert msgpack.decode[Color](hex.decode('a4626c7565')!)! == .blue
	assert msgpack.decode[Perm](hex.decode('a465786563')!)! == .exec
	for c in [Color.red, .green, .blue] {
		assert msgpack.decode[Color](msgpack.encode(c, enum_as_string: true)!)! == c
	}
}

fn test_decode_rejects_values_that_do_not_fit() {
	if _ := msgpack.decode[u8](msgpack.encode(300)!) {
		assert false
	} else {
		assert err is msgpack.IntRangeError
	}
	if _ := msgpack.decode[int](msgpack.encode(max_u64)!) {
		assert false
	} else {
		assert err is msgpack.IntRangeError
	}
	if _ := msgpack.decode[u32](msgpack.encode(-1)!) {
		assert false
	} else {
		assert err is msgpack.IntRangeError
	}
	if _ := msgpack.decode[bool](hex.decode('00')!) {
		assert false
	} else {
		assert err is msgpack.TypeMismatchError
	}
	if _ := msgpack.decode[int](hex.decode('c0')!) {
		assert false
	} else {
		assert err is msgpack.TypeMismatchError
	}
	if _ := msgpack.decode[Color](msgpack.encode(3)!) {
		assert false
	} else {
		assert err is msgpack.TypeMismatchError
	}
	if _ := msgpack.decode[[2]int](msgpack.encode([1, 2, 3])!) {
		assert false
	} else {
		assert err is msgpack.TypeMismatchError
	}
}

fn test_errors_locate_the_failing_value() {
	data := msgpack.encode({
		'places': [msgpack.Value(msgpack.Map{}), msgpack.Value(msgpack.Map{
			entries: [msgpack.MapEntry{'x', i64(1)}, msgpack.MapEntry{'y', 'oops'}]
		})]
	})!
	msgpack.decode[User](data) or {
		assert err is msgpack.TypeMismatchError
		assert err.msg().starts_with('msgpack: places[1].y: expected float, got str at offset')
		return
	}
	assert false
}

fn test_unknown_fields() {
	data := msgpack.encode({
		'city':    'Paris'
		'country': 'FR'
		'zip':     '75'
	})!
	assert msgpack.decode[Address](data)! == Address{'Paris', '75'}
	if _ := msgpack.decode[Address](data, deny_unknown_fields: true) {
		assert false
	} else {
		assert err is msgpack.UnknownFieldError
		assert err.msg().contains('"country"')
	}
}

fn test_duplicate_keys() {
	// {"city": "A", "city": "B"}
	data := hex.decode('82a463697479a141a463697479a142')!
	assert msgpack.decode[Address](data)!.city == 'B'
	assert msgpack.decode[map[string]string](data)!['city'] == 'B'
	if _ := msgpack.decode[Address](data, deny_duplicate_keys: true) {
		assert false
	} else {
		assert err is msgpack.DuplicateKeyError
	}
	if _ := msgpack.decode[map[string]string](data, deny_duplicate_keys: true) {
		assert false
	} else {
		assert err is msgpack.DuplicateKeyError
	}
}

fn test_trailing_bytes() {
	data := hex.decode('01c0')!
	if _ := msgpack.decode[int](data) {
		assert false
	} else {
		assert err is msgpack.MalformedError
	}
	assert msgpack.decode[int](data, allow_trailing_bytes: true)! == 1
}

fn test_truncated_struct_returns_an_error() {
	data := msgpack.encode(sample_user())!
	for cut in 0 .. data.len {
		if _ := msgpack.decode[User](data[..cut]) {
			assert false, 'accepted a message cut at ${cut}'
		}
	}
}

fn test_unpacker_restores_position_on_error() {
	data := msgpack.encode(['a', 'b'])!
	mut u := msgpack.new_unpacker(data)
	if _ := u.unpack[[]int]() {
		assert false
	}
	assert u.pos() == 0
	assert u.unpack[[]string]()! == ['a', 'b']
}

fn test_value_as_a_field() {
	data := msgpack.encode(Envelope{'ping', msgpack.Value([msgpack.Value(i64(1)), 'x'])})!
	env := msgpack.decode[Envelope](data)!
	assert env.payload.at(1)?.as_str()? == 'x'
}
