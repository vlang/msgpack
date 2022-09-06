module msgpack

import math

const (
	mp_nil             = u8(0xc0)
	// _               = u8(0xc1) // never used
	mp_false           = u8(0xc2)
	mp_true            = u8(0xc3)

	mp_pos_fix_int_min = u8(0x00)
	mp_pos_fix_int_max = u8(0x7f)
	mp_neg_fix_int_min = u8(0xe0)
	mp_neg_fix_int_max = u8(0xff)
	mp_u8              = u8(0xcc)
	mp_u16             = u8(0xcd)
	mp_u32             = u8(0xce)
	mp_u64             = u8(0xcf)
	mp_i8              = u8(0xd0)
	mp_i16             = u8(0xd1)
	mp_i32             = u8(0xd2)
	mp_i64             = u8(0xd3)
	mp_float           = u8(0xca)
	mp_double          = u8(0xcb)

	mp_fix_str_min     = u8(0xa0)
	mp_fix_str_max     = u8(0xbf)
	mp_str_8           = u8(0xd9)
	mp_str_16          = u8(0xda)
	mp_str_32          = u8(0xdb)

	mp_fix_array_min   = u8(0x90)
	mp_fix_array_max   = u8(0x9f)
	mp_array_16        = u8(0xdc)
	mp_array_32        = u8(0xdd)

	mp_fix_map_min     = u8(0x80)
	mp_fix_map_max     = u8(0x8f)
	mp_map_16          = u8(0xde)
	mp_map_32          = u8(0xdf)

	mp_bin_8           = u8(0xc4)
	mp_bin_16          = u8(0xc5)
	mp_bin_32          = u8(0xc6)

	mp_fix_ext_1       = u8(0xd4)
	mp_fix_ext_2       = u8(0xd5)
	mp_fix_ext_4       = u8(0xd6)
	mp_fix_ext_8       = u8(0xd7)
	mp_fix_ext_16      = u8(0xd8)
	mp_ext_8           = u8(0xc7)
	mp_ext_16          = u8(0xc8)
	mp_ext_32          = u8(0xc9)
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
