module msgpack

// NOTE: not using encoding.binary.put_x functions because its easier to use these
// and just pass uint & return the array rather than passing in a mutable array
pub fn put_u16(v u16) []u8 {
	return [
		u8(v >> 8),
		u8(v),
	]
}

pub fn put_u32(v u32) []u8 {
	return [
		u8(v >> 24),
		u8(v >> 16),
		u8(v >> 8),
		u8(v),
	]
}

pub fn put_u64(v u64) []u8 {
	return [
		u8(v >> 56),
		u8(v >> 48),
		u8(v >> 40),
		u8(v >> 32),
		u8(v >> 24),
		u8(v >> 16),
		u8(v >> 8),
		u8(v),
	]
}

// NOTE: we can use the encoding.binary.u_x functions for this
// pub fn u16(b [2]u8) u16 {
// 	return u16(b[1]) |
// 		u16(b[0])<<8
// }

// pub fn u32(b [4]u8) u32 {
// 	return u32(b[3]) |
// 		u32(b[2])<<8 |
// 		u32(b[1])<<16 |
// 		u32(b[0])<<24
// }

// pub fn u64(b [8]u8) u64 {
// 	return u64(b[7]) |
// 		u64(b[6])<<8 |
// 		u64(b[5])<<16 |
// 		u64(b[4])<<24 |
// 		u64(b[3])<<32 |
// 		u64(b[2])<<40 |
// 		u64(b[1])<<48 |
// 		u64(b[0])<<56
// }
