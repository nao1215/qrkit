//// Bit-level writer used by the standard QR encoder.

import gleam/bit_array
import gleam/int
import gleam/list
import qrkit/internal/util

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

pub fn append_byte(stream: BitStream, byte: Int) -> BitStream {
  append_bits(stream, byte, size: 8)
}

pub fn append_bytes(stream: BitStream, bytes: BitArray) -> BitStream {
  let BitStream(parts, length_bits) = stream
  BitStream([bytes, ..parts], length_bits + bit_array.bit_size(bytes))
}

pub fn pad_to_byte_boundary(stream: BitStream) -> BitStream {
  let remainder = length_bits(stream) % 8
  case remainder == 0 {
    True -> stream
    False -> append_bits(stream, 0, size: 8 - remainder)
  }
}

/// Append the pad codewords 0xEC and 0x11 in turn until a byte-aligned
/// `stream` holds `bytes` bytes.
pub fn append_pad_codewords(stream: BitStream, until bytes: Int) -> BitStream {
  let missing = bytes - length_bits(stream) / 8
  int.range(from: 0, to: int.max(missing, 0), with: stream, run: fn(acc, i) {
    case i % 2 {
      0 -> append_byte(acc, 0xEC)
      _ -> append_byte(acc, 0x11)
    }
  })
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

/// The bits of `bytes`, most significant bit of each byte first.
pub fn bytes_to_bits(bytes: List(Int)) -> List(Bool) {
  bytes
  |> list.fold([], fn(acc, byte) {
    [
      util.bit_at(byte, 0),
      util.bit_at(byte, 1),
      util.bit_at(byte, 2),
      util.bit_at(byte, 3),
      util.bit_at(byte, 4),
      util.bit_at(byte, 5),
      util.bit_at(byte, 6),
      util.bit_at(byte, 7),
      ..acc
    ]
  })
  |> list.reverse
}

/// Group `bits` into bytes, most significant bit first. A final group of
/// fewer than 8 bits is dropped.
pub fn bits_to_bytes(bits: List(Bool)) -> List(Int) {
  list.sized_chunk(bits, 8)
  |> list.filter(fn(chunk) { list.length(chunk) == 8 })
  |> list.map(bits_to_int)
}

/// The unsigned integer `bits` spell, most significant bit first.
pub fn bits_to_int(bits: List(Bool)) -> Int {
  list.fold(bits, 0, fn(acc, bit) { acc * 2 + util.bool_to_int(bit) })
}
