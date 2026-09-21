module msgpack

// Typed errors returned by the decoder. Every error carries the byte offset
// at which the problem was detected, and can be matched by the caller:
//
//   user := msgpack.decode[User](data) or {
//       if err is msgpack.UnexpectedEofError { ... }
//   }

// UnexpectedEofError is returned when the input ends before a complete value
// could be read, or when a declared length exceeds the remaining input.
pub struct UnexpectedEofError {
	Error
pub:
	pos       int // offset at which the read started
	need      i64 // number of bytes the decoder needed
	remaining int // number of bytes actually left
}

// msg formats the error for `IError.msg()`.
pub fn (e &UnexpectedEofError) msg() string {
	return 'msgpack: unexpected end of input at offset ${e.pos}: need ${e.need} byte(s), have ${e.remaining}'
}

// MalformedError is returned when the input is not valid MessagePack,
// e.g. the never-used format byte 0xc1 or an invalid timestamp payload.
pub struct MalformedError {
	Error
pub:
	pos    int
	reason string
}

// msg formats the error for `IError.msg()`.
pub fn (e &MalformedError) msg() string {
	return 'msgpack: malformed input at offset ${e.pos}: ${e.reason}'
}

// TypeMismatchError is returned when the next value has a different type
// than the one requested. `path` locates the value inside the decoded
// structure (e.g. `users[2].age`) when decoding through `decode[T]`.
pub struct TypeMismatchError {
	Error
pub:
	pos      int
	expected string
	got      string
pub mut:
	path string
}

// msg formats the error for `IError.msg()`.
pub fn (e &TypeMismatchError) msg() string {
	return 'msgpack: ${path_prefix(e.path)}expected ${e.expected}, got ${e.got} at offset ${e.pos}'
}

// IntRangeError is returned when an integer does not fit the requested
// V type, e.g. 300 decoded into a `u8` or -1 decoded into a `u64`.
pub struct IntRangeError {
	Error
pub:
	pos    int
	target string
	value  string
pub mut:
	path string
}

// msg formats the error for `IError.msg()`.
pub fn (e &IntRangeError) msg() string {
	return 'msgpack: ${path_prefix(e.path)}${e.value} does not fit in ${e.target} at offset ${e.pos}'
}

// MaxDepthError is returned when arrays and maps are nested deeper than
// `DecodeOpts.max_depth`.
pub struct MaxDepthError {
	Error
pub:
	pos       int
	max_depth int
}

// msg formats the error for `IError.msg()`.
pub fn (e &MaxDepthError) msg() string {
	return 'msgpack: nesting deeper than ${e.max_depth} levels at offset ${e.pos}'
}

// UnknownFieldError is returned by struct decoding when
// `DecodeOpts.deny_unknown_fields` is set and a key matches no field.
pub struct UnknownFieldError {
	Error
pub:
	pos  int
	name string
pub mut:
	path string
}

// msg formats the error for `IError.msg()`.
pub fn (e &UnknownFieldError) msg() string {
	return 'msgpack: ${path_prefix(e.path)}unknown field "${e.name}" at offset ${e.pos}'
}

// DuplicateKeyError is returned when `DecodeOpts.deny_duplicate_keys` is set
// and a map or struct contains the same key twice.
pub struct DuplicateKeyError {
	Error
pub:
	pos int
	key string
pub mut:
	path string
}

// msg formats the error for `IError.msg()`.
pub fn (e &DuplicateKeyError) msg() string {
	return 'msgpack: ${path_prefix(e.path)}duplicate key "${e.key}" at offset ${e.pos}'
}

// InvalidUtf8Error is returned when a str value is not valid UTF-8 and
// `DecodeOpts.validate_utf8` is set (the default).
pub struct InvalidUtf8Error {
	Error
pub:
	pos int
}

// msg formats the error for `IError.msg()`.
pub fn (e &InvalidUtf8Error) msg() string {
	return 'msgpack: invalid UTF-8 in str at offset ${e.pos}'
}

fn path_prefix(path string) string {
	return if path == '' { '' } else { '${path}: ' }
}

fn eof_error(pos int, need i64, remaining int) IError {
	return UnexpectedEofError{
		pos:       pos
		need:      need
		remaining: remaining
	}
}

fn malformed(pos int, reason string) IError {
	return MalformedError{
		pos:    pos
		reason: reason
	}
}

fn type_mismatch(pos int, expected string, got_byte u8) IError {
	return TypeMismatchError{
		pos:      pos
		expected: expected
		got:      format_name(got_byte)
	}
}

fn int_range(pos int, target string, value string) IError {
	return IntRangeError{
		pos:    pos
		target: target
		value:  value
	}
}
