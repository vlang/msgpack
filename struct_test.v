module main

import encoding.hex
import msgpack

struct Account {
	id       int      @[msgpack.Key: 'i']
	name     string   @[msgpack.Key: 'n']
	password string   @[skip]
	token    string   @[msgpack.Key: '-']
	note     string   @[omitempty]
	tags     []string @[omitempty]
	parent   ?int     @[omitempty]
	owner    string   @[required]
}

@[msgpack.RenameAll: 'camelCase']
struct Profile {
	first_name   string
	last_name    string
	home_address string @[msgpack.Key: 'addr']
}

@[msgpack.AsArray]
struct Pixel {
	x     u16
	y     u16
	color string
	cache int @[skip]
}

fn test_field_attributes() {
	a := Account{
		id:       1
		name:     'root'
		password: 'secret'
		token:    'abc'
		owner:    'me'
	}
	data := msgpack.encode(a)!
	// {"i": 1, "n": "root", "owner": "me"}
	assert data.hex() == '83a16901a16ea4726f6f74a56f776e6572a26d65'
	back := msgpack.decode[Account](data)!
	assert back.id == 1 && back.name == 'root' && back.owner == 'me'
	assert back.password == '' && back.token == ''

	full := Account{
		...a
		note:   'n'
		tags:   ['t']
		parent: 0
	}
	decoded := msgpack.decode[Account](msgpack.encode(full)!)!
	assert decoded.note == 'n'
	assert decoded.tags == ['t']
	assert decoded.parent or { -1 } == 0
}

fn test_skipped_fields_are_not_decoded() {
	data := msgpack.encode({
		'password': 'x'
		'owner':    'me'
	})!
	assert msgpack.decode[Account](data)!.password == ''
}

fn test_required_fields() {
	data := msgpack.encode({
		'i': 1
	})!
	msgpack.decode[Account](data) or {
		assert err is msgpack.MissingFieldError
		assert err.msg().contains('"owner"')
		return
	}
	assert false
}

fn test_rename_all() {
	p := Profile{'Ada', 'Lovelace', 'London'}
	data := msgpack.encode(p)!
	v := msgpack.decode[msgpack.Value](data)!
	assert v.get('firstName')?.as_str()? == 'Ada'
	assert v.get('lastName')?.as_str()? == 'Lovelace'
	assert v.get('addr')?.as_str()? == 'London'
	assert msgpack.decode[Profile](data)! == p
}

fn test_as_array() {
	px := Pixel{
		x:     1
		y:     300
		color: 'red'
		cache: 9
	}
	data := msgpack.encode(px)!
	assert data.hex() == '9301cd012ca3726564'
	back := msgpack.decode[Pixel](data)!
	assert back.x == 1 && back.y == 300 && back.color == 'red' && back.cache == 0
	// missing trailing elements keep their default, extra ones are skipped
	assert msgpack.decode[Pixel](hex.decode('9105')!)!.x == 5
	assert msgpack.decode[Pixel](hex.decode('940102a0c3')!)!.y == 2
	if _ := msgpack.decode[Pixel](hex.decode('940102a0c3')!, deny_unknown_fields: true) {
		assert false
	}
}

fn test_as_array_nested_in_a_map() {
	m := {
		'a': [Pixel{1, 2, 'x', 0}]
	}
	assert msgpack.decode[map[string][]Pixel](msgpack.encode(m)!)!['a'][0].color == 'x'
}

struct Clash {
	a int @[msgpack.Key: 'k']
	b int @[msgpack.Key: 'k']
}

fn test_fields_with_the_same_key_are_rejected() {
	if _ := msgpack.encode(Clash{}) {
		assert false
	} else {
		assert err.msg().contains('"k"')
	}
	if _ := msgpack.decode[Clash](msgpack.encode({
		'k': 1
	})!) {
		assert false
	}
}

@[msgpack.RenameAll: 'camelCase']
struct Shared {
	first_field  int
	second_field string @[omitempty]
}

fn encode_shared(i int) []u8 {
	return msgpack.encode(Shared{i, 'x'}) or { panic(err) }
}

// The field metadata of a struct type is computed on its first use, which
// several threads may reach at once.
fn test_struct_metadata_is_shared_by_threads() {
	mut threads := []thread []u8{}
	for i in 0 .. 8 {
		threads << spawn encode_shared(i)
	}
	results := threads.wait()
	for i, data in results {
		back := msgpack.decode[Shared](data)!
		assert back.first_field == i && back.second_field == 'x'
	}
}
