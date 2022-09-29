# vlang msgpack encoder/decoder module

MessagePack is an efficient binary serialization format. It's like JSON. but fast and small.

View the specification: https://github.com/msgpack/msgpack

# Status

The changes required to run this have now been merged into v master.

## Encoding
Working for all basic types, with support for the time extension. Support for custom extensions will be added soon.

## Decoding
It is still not possible to decode to a data structure, currently decode only prints the decoded data. This will be implemented soon.

# Examples

You can see some basic examples are in the `examples/` directory
