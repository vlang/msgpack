module msgpack

import math

// Spec: https://github.com/msgpack/msgpack/blob/master/spec.md
const (
	// 7-bit positive integer
	mp_pos_fix_int_min = u8(0x00)
	mp_pos_fix_int_max = u8(0x7f)
	// map whose length is up to 15 elements
	mp_fix_map_min     = u8(0x80)
	mp_fix_map_max     = u8(0x8f)
	// array whose length is up to 15 elements
	mp_fix_array_min   = u8(0x90)
	mp_fix_array_max   = u8(0x9f)
	// byte array whose length is up to 31 bytes
	mp_fix_str_min     = u8(0xa0)
	mp_fix_str_max     = u8(0xbf)
	// nil
	mp_nil             = u8(0xc0)
	// _               = u8(0xc1) // never used
	// booleans
	mp_false           = u8(0xc2)
	mp_true            = u8(0xc3)
	// byte array whose length is up to:
	mp_bin_8           = u8(0xc4) //  (2^8)-1 bytes
	mp_bin_16          = u8(0xc5) // (2^16)-1 bytes (big-endian)
	mp_bin_32          = u8(0xc6) // (2^32)-1 bytes (big-endian)
	// integer and a byte array whose length is up to:
	mp_ext_8           = u8(0xc7) //  (2^8)-1 bytes
	mp_ext_16          = u8(0xc8) // (2^16)-1 bytes (big-endian)
	mp_ext_32          = u8(0xc9) // (2^32)-1 bytes (big-endian)
	// single|double precision floating point number (big-endian, IEEE 754)
	mp_f32             = u8(0xca)
	mp_f64             = u8(0xcb)
	// 8-bit unsigned integer
	mp_u8              = u8(0xcc)
	// 16|32|64-bit unsigned integer (big-endian)
	mp_u16             = u8(0xcd)
	mp_u32             = u8(0xce)
	mp_u64             = u8(0xcf)
	// 8-bit signed integer
	mp_i8              = u8(0xd0)
	// 16|32|64-bit signed integer (big-endian)
	mp_i16             = u8(0xd1)
	mp_i32             = u8(0xd2)
	mp_i64             = u8(0xd3)
	// integer and a byte array whose length is:
	mp_fix_ext_1       = u8(0xd4) //  1 byte
	mp_fix_ext_2       = u8(0xd5) //  2 bytes
	mp_fix_ext_4       = u8(0xd6) //  4 bytes
	mp_fix_ext_8       = u8(0xd7) //  8 bytes
	mp_fix_ext_16      = u8(0xd8) // 16 bytes
	// byte array whose length is up to:
	mp_str_8           = u8(0xd9) //  (2^8)-1 bytes
	mp_str_16          = u8(0xda) // (2^16)-1 bytes (big-endian)
	mp_str_32          = u8(0xdb) // (2^32)-1 bytes (big-endian)
	// array whose length is up to (big-endian):
	mp_array_16        = u8(0xdc) // (2^16)-1 elements
	mp_array_32        = u8(0xdd) // (2^32)-1 elements
	// map whose length is up to (big-endian):
	mp_map_16          = u8(0xde) // (2^16)-1 elements
	mp_map_32          = u8(0xdf) // (2^32)-1 elements
	// 5-bit negative integer
	mp_neg_fix_int_min = u8(0xe0)
	mp_neg_fix_int_max = u8(0xff)
)

const (
	mp_time_ext_type = u8(-1)
)

const (
	// containerLenUnknown is length returned from Read(Map|Array)Len
	// when a format doesn't know apiori.
	// For example, json doesn't pre-determine the length of a container (sequence/map).
	container_len_unknown = -1

	// containerLenNil is length returned from Read(Map|Array)Len
	// when a 'nil' was encountered in the stream.
	container_len_nil     = math.min_i32
)

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
struct MsgpackContainerType {
	fix_cutoff u8
	b_fix_min  u8
	b8         u8
	b16        u8
	b32        u8
	// hasFixMin, has8, has8Always bool
}

const (
	msgpack_container_raw_legacy = MsgpackContainerType{32, mp_fix_str_min, 0, mp_str_16, mp_str_32}
	msgpack_container_str        = MsgpackContainerType{32, mp_fix_str_min, mp_str_8, mp_str_16, mp_str_32}
	msgpack_container_bin        = MsgpackContainerType{0, 0, mp_bin_8, mp_bin_16, mp_bin_32}
	msgpack_container_list       = MsgpackContainerType{16, mp_fix_array_min, 0, mp_array_16, mp_array_32}
	msgpack_container_map        = MsgpackContainerType{16, mp_fix_map_min, 0, mp_map_16, mp_map_32}
)

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

// var valueTypeStrings = [...]string{
// 	"Unset",
// 	"Nil",
// 	"Int",
// 	"Uint",
// 	"Float",
// 	"Bool",
// 	"String",
// 	"Symbol",
// 	"Bytes",
// 	"Map",
// 	"Array",
// 	"Timestamp",
// 	"Ext",
// }
