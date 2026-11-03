module msgpack

import io
import os

const stream_chunk_size = 64 * 1024

// StreamDecoder reads consecutive MessagePack values from an `io.Reader`,
// such as a file or a socket. Once a value is complete it is returned
// without reading further, so the decoder never waits for data past the end
// of a message (it may still keep bytes of the next ones, read ahead in the
// same chunk).
//
//   mut d := msgpack.new_stream_decoder(conn)
//   for {
//       req := d.decode[Request]() or {
//           if err is io.Eof { break }
//           return err
//       }
//       ...
//   }
pub struct StreamDecoder {
	opts DecodeOpts
mut:
	reader  io.Reader
	buf     []u8 // received bytes, unread from `start`
	chunk   []u8 // read buffer
	start   int
	scan    int // where the walk through the current value resumes
	pending i64 // values left in that walk; 0 when no walk is in progress
	eof     bool
}

// new_stream_decoder returns a StreamDecoder reading from `reader`.
pub fn new_stream_decoder(reader io.Reader, opts DecodeOpts) StreamDecoder {
	return StreamDecoder{
		opts:   opts
		reader: reader
		chunk:  []u8{len: stream_chunk_size}
	}
}

// decode reads the next value of the stream into a `T`. It returns `io.Eof`
// when the stream ends cleanly between two values, and an
// `UnexpectedEofError` when it ends inside a value.
pub fn (mut d StreamDecoder) decode[T]() !T {
	end := d.next_value_end()!
	data := d.buf[d.start..end]
	d.start = end
	return decode[T](data, d.opts)!
}

// next_value_end returns the offset in `buf` just past the next value,
// reading from the stream until that value is complete. The walk through the
// value is resumed after each read, so a value arriving in many small pieces
// is still scanned only once.
fn (mut d StreamDecoder) next_value_end() !int {
	if d.pending == 0 {
		d.scan = d.start
		d.pending = 1
	}
	for {
		mut u := Unpacker{
			data:    d.buf
			opts:    d.opts
			cur:     d.scan
			pending: d.pending
		}
		u.skip_pending() or {
			if err !is UnexpectedEofError {
				d.pending = 0
				return err
			}
			d.scan = u.cur
			d.pending = u.pending
			if d.eof {
				if d.start == d.buf.len {
					d.pending = 0
					return io.Eof{}
				}
				return err
			}
			if d.buf.len - d.start >= d.opts.max_buffer_size {
				return error('msgpack: a value exceeds max_buffer_size (${d.opts.max_buffer_size} bytes)')
			}
			d.fill()!
			continue
		}
		d.pending = 0
		if u.cur - d.start > d.opts.max_buffer_size {
			return error('msgpack: a value exceeds max_buffer_size (${d.opts.max_buffer_size} bytes)')
		}
		return u.cur
	}
	return error('unreachable')
}

// fill appends the next chunk of the stream to `buf`. The bytes already
// decoded are dropped once they fill half of it, so that each byte is moved
// a bounded number of times.
fn (mut d StreamDecoder) fill() ! {
	if d.start > 0 && d.start >= d.buf.len / 2 {
		n := d.buf.len - d.start
		copy(mut d.buf, d.buf[d.start..])
		d.buf.trim(n)
		d.scan -= d.start
		d.start = 0
	}
	n := d.reader.read(mut d.chunk) or {
		// files report the end with os.Eof, other readers with io.Eof
		if err is io.Eof || err is os.Eof {
			d.eof = true
			return
		}
		return err
	}
	if n <= 0 {
		d.eof = true
		return
	}
	unsafe { d.buf.push_many(d.chunk.data, n) }
}

// StreamEncoder writes consecutive MessagePack values to an `io.Writer`.
pub struct StreamEncoder {
mut:
	writer io.Writer
	packer Packer
}

// new_stream_encoder returns a StreamEncoder writing to `writer`.
pub fn new_stream_encoder(writer io.Writer, opts EncodeOpts) StreamEncoder {
	return StreamEncoder{
		writer: writer
		packer: new_packer(opts)
	}
}

// encode writes `val` to the stream. The value is encoded in full before
// anything is written, so an encoding error writes nothing.
pub fn (mut e StreamEncoder) encode[T](val T) ! {
	e.packer.reset()
	e.packer.pack(val)!
	data := e.packer.buf
	mut written := 0
	for written < data.len {
		n := e.writer.write(data[written..])!
		if n <= 0 {
			return error('msgpack: the writer accepted no bytes')
		}
		written += n
	}
}
