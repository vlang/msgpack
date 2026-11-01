module msgpack

// Key gives a struct field another key in the encoded map. `@[msgpack.Key: '-']`
// leaves the field out, like `@[skip]`.
//
// The attributes of this module are declared as attribute schemas, so the
// compiler checks them; they are written qualified by the module name:
//
// ```v ignore
// struct User {
// 	id int @[msgpack.Key: 'ID']
// }
// ```
@[attribute: 'field']
pub struct Key {
pub:
	name string
}

// RenameAll renames every field of a struct: `@[msgpack.RenameAll: 'camelCase']`.
// The styles are `camelCase`, `snake_case`, `PascalCase`, `kebab-case` and
// `SCREAMING_SNAKE_CASE`.
@[attribute: 'struct']
pub struct RenameAll {
pub:
	style string
}

// AsArray writes the fields of a struct as an array, in declaration order,
// instead of a map: `@[msgpack.AsArray]`.
@[attribute: 'struct']
pub struct AsArray {}
