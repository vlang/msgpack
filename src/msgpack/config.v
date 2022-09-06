module msgpack

// TODO: clean this up, simplify comments and unneeded remove remnants from go lib
struct Config {
	// no_fixed_num says to output all signed integers as 2-bytes, never as 1-byte fixednum.
	no_fixed_num bool

	// write_ext controls whether the new spec is honored.
	//
	// With write_ext=true, we can encode configured extensions with extension tags
	// and encode string/[]byte/extensions in a way compatible with the new spec
	// but incompatible with the old spec.
	//
	// For compatibility with the old spec, set write_ext=false.
	//
	// With write_ext=false:
	//    configured extensions are serialized as raw bytes (not msgpack extensions).
	//    reserved byte descriptors like Str8 and those enabling the new msgpack Binary type
	//    are not encoded.
	write_ext bool

	// positive_int_unsigned says to encode positive integers as unsigned.
	positive_int_unsigned bool

	// string_to_raw controls how strings are encoded.
	//
	// As a go string is just an (immutable) sequence of bytes,
	// it can be encoded either as raw bytes or as a UTF string.
	//
	// By default, strings are encoded as UTF-8.
	// but can be treated as []byte during an encode.
	//
	// Note that things which we know (by definition) to be UTF-8
	// are ALWAYS encoded as UTF-8 strings.
	// These include encoding.TextMarshaler, time.Format calls, struct field names, etc.
	// raw_to_string controls how raw bytes in a stream are decoded into a nil interface{}.
	// By default, they are decoded as []byte, but can be decoded as string (if configured).
	string_raw bool
}

pub fn default_config() Config {
	return Config{
		write_ext: true
	}
}
