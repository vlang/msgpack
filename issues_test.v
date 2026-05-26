module main

import json
import msgpack
import encoding.hex

// Regression tests captured directly from the bug reports that motivated each
// fix. Keep each block self-contained and labeled with the issue number so
// reviewers can trace the failure mode back to the original report.

// vlang/v#26644 — bug 1: encoder used the widest integer format unconditionally,
// producing wire-format bytes incompatible with every spec-compliant
// MessagePack implementation. Cross-language byte values are taken from
// Python's `msgpack.packb` in the issue.
fn test_v_26644_bug1_encoder_uses_minimal_int_format() {
	assert msgpack.encode(0) == hex.decode('00')!
	assert msgpack.encode(42) == hex.decode('2a')!
	assert msgpack.encode(127) == hex.decode('7f')!
	assert msgpack.encode(-1) == hex.decode('ff')!
	assert msgpack.encode(-32) == hex.decode('e0')!
	assert msgpack.encode(-123) == hex.decode('d085')!
	assert msgpack.encode(1) == hex.decode('01')!

	// Container with integer values should also use minimal encoding.
	assert msgpack.encode([0]) == hex.decode('9100')!
	assert msgpack.encode([1, 2, 3]) == hex.decode('93010203')!
}

// vlang/v#26644 — bug 2: `positive_int_unsigned` defaulted to false, so
// non-negative values in 128–255 took the signed branch and produced 3-byte
// int16 instead of 2-byte uint8. The 2-byte form is the spec-mandated minimal
// encoding.
fn test_v_26644_bug2_positive_values_use_unsigned_family() {
	assert msgpack.encode(200) == hex.decode('ccc8')!
	assert msgpack.encode(255) == hex.decode('ccff')!
	assert msgpack.encode(128) == hex.decode('cc80')!
}

// vlang/v#26644 — bug 3: decoder had no match arms for positive fixint
// (0x00–0x7f) or negative fixint (0xe0–0xff), so any value in -32..127 encoded
// by a spec-compliant library was rejected as "invalid integer descriptor
// byte". After bug 1 was fixed the decoder also could not round-trip its own
// output.
fn test_v_26644_bug3_decoder_handles_fixint_bytes() {
	// Positive fixint (format byte IS the value).
	assert msgpack.decode[int](hex.decode('00')!)! == 0
	assert msgpack.decode[int](hex.decode('2a')!)! == 42
	assert msgpack.decode[int](hex.decode('7f')!)! == 127

	// Negative fixint (format byte reinterpreted as signed i8).
	assert msgpack.decode[int](hex.decode('e0')!)! == -32
	assert msgpack.decode[int](hex.decode('fb')!)! == -5
	assert msgpack.decode[int](hex.decode('ff')!)! == -1
}

// vlang/v#26644 — combined: after all three fixes, encode → decode is an
// identity round-trip across the fixint, uint8 and int8 boundaries that
// previously triggered each individual bug.
fn test_v_26644_integer_round_trip() {
	values := [0, 1, 42, 127, 128, 200, 255, -1, -5, -32, -33, -123, -128]
	for v in values {
		assert msgpack.decode[int](msgpack.encode(v))! == v
	}
}

// vlang/msgpack#12 — the encoder produced valid bytes for a 1-field struct
// (`Map{used_ids: int}`), but `decode_struct` never read the map header or the
// key, so it interpreted the first byte of the key ("u" = 0x75 = 117) as an
// integer descriptor and panicked with "invalid integer descriptor byte 117".
pub struct UsedIdsMap {
	used_ids int
}

fn test_msgpack_12_struct_decode_round_trip() {
	value := UsedIdsMap{
		used_ids: 1
	}
	encoded := msgpack.encode[UsedIdsMap](value)
	// The bug report showed `81a8...d200000001` (int32-encoded `1`); after the
	// v#26644 fix the value is now a single positive-fixint byte.
	assert encoded.hex() == '81a8757365645f69647301'
	// Decode is what panicked before with "invalid integer descriptor byte 117".
	decoded := msgpack.decode[UsedIdsMap](encoded)!
	assert decoded == value

	// Pre-fix wire bytes from the issue must also decode (proves the bug isn't
	// hidden by the encoder now picking a different format).
	pre_fix := hex.decode('81a8757365645f696473d200000001')!
	assert msgpack.decode[UsedIdsMap](pre_fix)! == value
}

// vlang/msgpack#12 — full code path from the bug report, including the
// json.decode → msgpack.encode → msgpack.decode pipeline the reporter used.
fn test_msgpack_12_json_to_msgpack_round_trip() {
	data := '{"used_ids": 1}'
	json_data := json.decode(UsedIdsMap, data)!
	encoded := msgpack.encode[UsedIdsMap](json_data)
	decoded := msgpack.decode[UsedIdsMap](encoded)!
	assert decoded == UsedIdsMap{
		used_ids: 1
	}
}
