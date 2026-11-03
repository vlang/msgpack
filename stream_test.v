module main

import io
import msgpack
import os
import rand

// ChunkedReader returns its data in pieces of at most `size` bytes.
struct ChunkedReader {
	data []u8
	size int
mut:
	pos   int
	reads int
}

fn (mut r ChunkedReader) read(mut buf []u8) !int {
	if r.pos >= r.data.len {
		return io.Eof{}
	}
	mut n := if r.size > 0 { r.size } else { rand.intn(7) or { 0 } + 1 }
	n = if n > buf.len { buf.len } else { n }
	n = if n > r.data.len - r.pos { r.data.len - r.pos } else { n }
	copy(mut buf, r.data[r.pos..r.pos + n])
	r.pos += n
	r.reads++
	return n
}

struct Buffer {
mut:
	data []u8
}

fn (mut b Buffer) write(buf []u8) !int {
	// accept at most 3 bytes per call, to exercise partial writes
	n := if buf.len > 3 { 3 } else { buf.len }
	b.data << buf[..n]
	return n
}

struct Msg {
	id   int
	body string
	tags []string
}

fn messages() []Msg {
	return [
		Msg{1, 'hello', ['a']},
		Msg{2, 'x'.repeat(70000), []},
		Msg{3, '', ['b', 'c']},
	]
}

fn encoded_stream() []u8 {
	mut w := &Buffer{}
	mut e := msgpack.new_stream_encoder(w)
	for m in messages() {
		e.encode(m) or { panic(err) }
	}
	return w.data
}

fn test_stream_round_trip_with_any_chunking() {
	data := encoded_stream()
	for size in [0, 1, 2, 5, 64 * 1024] {
		mut d := msgpack.new_stream_decoder(ChunkedReader{
			data: data
			size: size
		})
		for want in messages() {
			assert d.decode[Msg]()! == want, 'chunk size ${size}'
		}
		if _ := d.decode[Msg]() {
			assert false
		} else {
			assert err is io.Eof
		}
	}
}

fn test_stream_large_value_arriving_byte_by_byte() {
	data := msgpack.encode('x'.repeat(70000))!
	mut d := msgpack.new_stream_decoder(ChunkedReader{
		data: data
		size: 1
	})
	assert d.decode[string]()!.len == 70000
}

// BlockingReader serves one message, then fails like a socket with nothing
// left to read would block.
struct BlockingReader {
	data []u8
mut:
	pos int
}

fn (mut r BlockingReader) read(mut buf []u8) !int {
	if r.pos >= r.data.len {
		return error('would block')
	}
	buf[0] = r.data[r.pos]
	r.pos++
	return 1
}

fn test_stream_does_not_read_past_a_complete_value() {
	mut d := msgpack.new_stream_decoder(BlockingReader{
		data: msgpack.encode([1, 2, 3])!
	})
	assert d.decode[[]int]()! == [1, 2, 3]
	if _ := d.decode[[]int]() {
		assert false
	} else {
		assert err.msg() == 'would block'
	}
}

fn test_stream_truncated_value() {
	data := msgpack.encode(Msg{1, 'hello', []})!
	mut d := msgpack.new_stream_decoder(ChunkedReader{
		data: data[..data.len - 2]
		size: 3
	})
	if _ := d.decode[Msg]() {
		assert false
	} else {
		assert err is msgpack.UnexpectedEofError
	}
}

fn test_stream_limits_the_buffer() {
	// a str header declaring 4 GiB
	mut d := msgpack.new_stream_decoder(ChunkedReader{
		data: [u8(0xdb), 0xff, 0xff, 0xff, 0xff].repeat(1000)
		size: 1024
	},
		max_buffer_size: 100
	)
	if _ := d.decode[string]() {
		assert false
	} else {
		assert err.msg().contains('max_buffer_size')
	}
}

fn test_stream_reports_malformed_data() {
	mut d := msgpack.new_stream_decoder(ChunkedReader{
		data: [u8(0xc1)]
		size: 1
	})
	if _ := d.decode[int]() {
		assert false
	} else {
		assert err is msgpack.MalformedError
	}
}

fn test_stream_limits_complete_values_too() {
	// a complete 200-byte value arriving in one chunk
	mut d := msgpack.new_stream_decoder(ChunkedReader{
		data: msgpack.encode('x'.repeat(200))!
		size: 1024
	},
		max_buffer_size: 100
	)
	if _ := d.decode[string]() {
		assert false
	} else {
		assert err.msg().contains('max_buffer_size')
	}
}

fn test_stream_through_a_file() {
	path := os.join_path(os.vtmp_dir(), 'msgpack_stream_test_${os.getpid()}.bin')
	defer {
		os.rm(path) or {}
	}
	mut output := os.create(path)!
	mut e := msgpack.new_stream_encoder(output)
	for m in messages() {
		e.encode(m)!
	}
	output.close()
	mut input := os.open(path)!
	defer {
		input.close()
	}
	mut d := msgpack.new_stream_decoder(input)
	for want in messages() {
		assert d.decode[Msg]()! == want
	}
	if _ := d.decode[Msg]() {
		assert false
	} else {
		assert err is io.Eof
	}
}
