module msgpack

// Spec: https://github.com/msgpack/msgpack/blob/master/spec.md
// 7-bit positive integer
const mp_pos_fix_int_min = u8(0x00)
const mp_pos_fix_int_max = u8(0x7f)
// map whose length is up to 15 elements
const mp_fix_map_min = u8(0x80)
const mp_fix_map_max = u8(0x8f)
// array whose length is up to 15 elements
const mp_fix_array_min = u8(0x90)
const mp_fix_array_max = u8(0x9f)
// byte array whose length is up to 31 bytes
const mp_fix_str_min = u8(0xa0)
const mp_fix_str_max = u8(0xbf)
// nil
const mp_nil = u8(0xc0)
// _               = u8(0xc1) // never used
// booleans
const mp_false = u8(0xc2)
const mp_true = u8(0xc3)
// byte array whose length is up to:
const mp_bin_8 = u8(0xc4)
//  (2^8)-1 bytes
const mp_bin_16 = u8(0xc5)
// (2^16)-1 bytes (big-endian)
const mp_bin_32 = u8(0xc6)
// (2^32)-1 bytes (big-endian)
// integer and a byte array whose length is up to:
const mp_ext_8 = u8(0xc7)
//  (2^8)-1 bytes
const mp_ext_16 = u8(0xc8)
// (2^16)-1 bytes (big-endian)
const mp_ext_32 = u8(0xc9)
// (2^32)-1 bytes (big-endian)
// single|double precision floating point number (big-endian, IEEE 754)
const mp_f32 = u8(0xca)
const mp_f64 = u8(0xcb)
// 8|16|32|64-bit unsigned integer
const mp_u8 = u8(0xcc)
const mp_u16 = u8(0xcd)
// (big-endian)
const mp_u32 = u8(0xce)
// (big-endian)
const mp_u64 = u8(0xcf)
// (big-endian)
// 8|16|32|64-bit signed integer
const mp_i8 = u8(0xd0)
const mp_i16 = u8(0xd1)
// (big-endian)
const mp_i32 = u8(0xd2)
// (big-endian)
const mp_i64 = u8(0xd3)
// (big-endian)
// integer and a byte array whose length is:
const mp_fix_ext_1 = u8(0xd4)
//  1 byte
const mp_fix_ext_2 = u8(0xd5)
//  2 bytes
const mp_fix_ext_4 = u8(0xd6)
//  4 bytes
const mp_fix_ext_8 = u8(0xd7)
//  8 bytes
const mp_fix_ext_16 = u8(0xd8)
// 16 bytes
// byte array whose length is up to:
const mp_str_8 = u8(0xd9)
//  (2^8)-1 bytes
const mp_str_16 = u8(0xda)
// (2^16)-1 bytes (big-endian)
const mp_str_32 = u8(0xdb)
// (2^32)-1 bytes (big-endian)
// array whose length is up to (big-endian):
const mp_array_16 = u8(0xdc)
// (2^16)-1 elements
const mp_array_32 = u8(0xdd)
// (2^32)-1 elements
// map whose length is up to (big-endian):
const mp_map_16 = u8(0xde)
// (2^16)-1 elements
const mp_map_32 = u8(0xdf)
// (2^32)-1 elements
// 5-bit negative integer
const mp_neg_fix_int_min = u8(0xe0)
const mp_neg_fix_int_max = u8(0xff)

// Applications can assign 0 to 127 to store application-specific type information.
// MessagePack reserves -1 to -128 for future extension to add predefined types.
// Timestamp
const mp_time_ext_type = u8(-1)

// container_len_unknown is length returned from read_(map|array)_len
// when a format doesn't prefix the length.
// For example, json doesn't pre-determine the length of a container (sequence/map).
// container_len_unknown = -1
// container_len_nil is length returned from read_(map|array)_len
// when a 'nil' was encountered in the stream.
const container_len_nil = min_i32

struct RawExt {
	tag u64
	// Data is the []byte which represents the raw ext. If nil, ext is exposed in Value.
	// Data is used by codecs (e.g. binc, msgpack, simple) which do custom serialization of types
	data []u8
	// Value represents the extension, if Data is nil.
	// Value is used by codecs (e.g. cbor, json) which leverage the format to do
	// custom serialization of the types.
	// Value interface{}
}

// A MsgpackContainer type specifies the different types of msgpackContainers.
struct ContainerType {
	fix_cutoff u8
	b_fix_min  u8
	b8         u8
	b16        u8
	b32        u8
}

const container_raw_legacy = ContainerType{32, mp_fix_str_min, 0, mp_str_16, mp_str_32}
const container_str = ContainerType{32, mp_fix_str_min, mp_str_8, mp_str_16, mp_str_32}
const container_bin = ContainerType{0, 0, mp_bin_8, mp_bin_16, mp_bin_32}
const container_array = ContainerType{16, mp_fix_array_min, 0, mp_array_16, mp_array_32}
const container_map = ContainerType{16, mp_fix_map_min, 0, mp_map_16, mp_map_32}

// valueType is the stream type
enum ValueType {
	unset
	nil_
	int_
	uint
	float
	bool_
	string_
	symbol
	bytes
	map_
	array
	time
	ext
	// valueTypeInvalid
}
