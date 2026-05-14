//// Bit-level writer used by the standard QR encoder.

import gleam/bit_array
import gleam/list

pub opaque type BitStream {
  BitStream(parts: List(BitArray), length_bits: Int)
}

pub fn new() -> BitStream {
  BitStream([], 0)
}

pub fn length_bits(stream: BitStream) -> Int {
  let BitStream(_, length_bits) = stream
  length_bits
}

pub fn append_bits(stream: BitStream, value: Int, size bits: Int) -> BitStream {
  let BitStream(parts, length_bits) = stream
  BitStream([<<value:size(bits)>>, ..parts], length_bits + bits)
}

pub fn append_bit(stream: BitStream, value: Bool) -> BitStream {
  case value {
    True -> append_bits(stream, 1, size: 1)
    False -> append_bits(stream, 0, size: 1)
  }
}

pub fn append_byte(stream: BitStream, byte: Int) -> BitStream {
  append_bits(stream, byte, size: 8)
}

pub fn append_bytes(stream: BitStream, bytes: BitArray) -> BitStream {
  let BitStream(parts, length_bits) = stream
  BitStream([bytes, ..parts], length_bits + bit_array.bit_size(bytes))
}

pub fn concat(streams: List(BitStream)) -> BitStream {
  list.fold(streams, new(), fn(acc, stream) {
    append_bytes(acc, to_bit_array(stream))
  })
}

pub fn pad_to_byte_boundary(stream: BitStream) -> BitStream {
  let remainder = length_bits(stream) % 8
  case remainder == 0 {
    True -> stream
    False -> append_bits(stream, 0, size: 8 - remainder)
  }
}

pub fn to_bit_array(stream: BitStream) -> BitArray {
  let BitStream(parts, _) = stream
  parts |> list.reverse |> bit_array.concat
}

pub fn to_byte_list(stream: BitStream) -> List(Int) {
  do_to_byte_list(to_bit_array(stream), [])
}

fn do_to_byte_list(bits: BitArray, acc: List(Int)) -> List(Int) {
  case bits {
    <<>> -> list.reverse(acc)
    <<byte, rest:bytes>> -> do_to_byte_list(rest, [byte, ..acc])
    _ -> list.reverse(acc)
  }
}
