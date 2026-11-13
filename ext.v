module msgpack

import time

// timestamp_ext_type is the extension type reserved by the MessagePack spec
// for timestamps.
pub const timestamp_ext_type = i8(-1)

// Ext is an extension value: an application-defined type identifier and an
// opaque payload. Types 0..127 are free for applications; -128..-1 are
// reserved by the spec (-1 is the timestamp).
pub struct Ext {
pub:
	type_id i8
	data    []u8
}

// Timestamp is the MessagePack timestamp extension (type -1): seconds since
// the Unix epoch plus nanoseconds. It covers the full range of the wire
// format, which is wider than what `time.Time` can represent.
pub struct Timestamp {
pub:
	seconds     i64
	nanoseconds u32 // 0..999_999_999
}

// Seconds from 0001-01-01T00:00:00Z to 9999-12-31T23:59:59Z: the years to
// which conversions to `time.Time` are limited.
const min_time_seconds = i64(-62_135_596_800)
const max_time_seconds = i64(253_402_300_799)

// Timestamp.from_time converts a `time.Time` to a Timestamp, without loss.
// It fails if the nanosecond field is outside 0..999999999.
pub fn Timestamp.from_time(t time.Time) !Timestamp {
	if t.nanosecond < 0 || t.nanosecond > 999_999_999 {
		return error('msgpack: time nanosecond ${t.nanosecond} is outside 0..999999999')
	}
	return Timestamp{
		seconds:     t.unix()
		nanoseconds: u32(t.nanosecond)
	}
}

// to_time converts the timestamp to a UTC `time.Time`. It fails when the
// timestamp is outside the years 1..9999, or its nanoseconds exceed
// 999999999.
pub fn (ts Timestamp) to_time() !time.Time {
	if ts.nanoseconds > 999_999_999 {
		return error('msgpack: timestamp nanoseconds ${ts.nanoseconds} exceed 999999999')
	}
	if ts.seconds < min_time_seconds || ts.seconds > max_time_seconds {
		return error('msgpack: timestamp ${ts.seconds}s is outside the years 1..9999')
	}
	return time.unix_nanosecond(ts.seconds, int(ts.nanoseconds))
}
