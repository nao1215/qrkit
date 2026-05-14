//// Structured Append for standard QR codes (ISO/IEC 18004 §8.2).
////
//// Splits a long input into up to 16 shards, each carrying a 20-bit Structured
//// Append header (mode `0011` + symbol position + total-1 + parity byte) so
//// readers can reassemble the original message.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import qrkit/error.{
  type EncodeError, type ErrorCorrection, Auto, DataExceedsCapacity, EmptyInput,
  InvalidVersion,
}
import qrkit/internal/bitstream
import qrkit/internal/standard
import qrkit/internal/util

/// Upper bound on the number of shards allowed by ISO/IEC 18004 §8.2.
pub const max_symbols: Int = 16

/// Encode the data using as few shards as possible while respecting
/// `max_version` per shard. Returns a list of `standard.Encoded` symbols.
pub fn encode(
  data: String,
  max_version: Int,
  ecc: ErrorCorrection,
) -> Result(List(standard.Encoded), EncodeError) {
  case data == "" {
    True -> Error(EmptyInput)
    False ->
      case max_version < 1 || max_version > 40 {
        True -> Error(InvalidVersion(max_version))
        False -> find_split(data, max_version, ecc, 1)
      }
  }
}

/// Compute the parity byte (XOR of all UTF-8 bytes of `data`).
pub fn parity_of(data: String) -> Int {
  parity_of_bits(bit_array.from_string(data), 0)
}

fn parity_of_bits(bytes: BitArray, acc: Int) -> Int {
  case bytes {
    <<>> -> acc
    <<byte:size(8), rest:bits>> ->
      parity_of_bits(rest, int.bitwise_exclusive_or(acc, byte))
    _ -> acc
  }
}

fn find_split(
  data: String,
  max_version: Int,
  ecc: ErrorCorrection,
  total: Int,
) -> Result(List(standard.Encoded), EncodeError) {
  case total > max_symbols {
    True -> Error(DataExceedsCapacity(bits_needed: 0, bits_available: 0))
    False -> {
      let chunks = split_string(data, total)
      case encode_shards(chunks, data, total, max_version, ecc) {
        Ok(encodes) -> Ok(encodes)
        Error(_) -> find_split(data, max_version, ecc, total + 1)
      }
    }
  }
}

fn encode_shards(
  chunks: List(String),
  data: String,
  total: Int,
  max_version: Int,
  ecc: ErrorCorrection,
) -> Result(List(standard.Encoded), EncodeError) {
  case total {
    1 ->
      case chunks {
        [chunk] ->
          case
            standard.encode_prefixed(
              chunk,
              ecc,
              1,
              max_version,
              None,
              Auto,
              <<>>,
            )
          {
            Ok(encoded) -> Ok([encoded])
            Error(error) -> Error(error)
          }
        _ -> Error(EmptyInput)
      }
    _ -> encode_multiple_shards(chunks, data, total, max_version, ecc, 0, [])
  }
}

fn encode_multiple_shards(
  chunks: List(String),
  data: String,
  total: Int,
  max_version: Int,
  ecc: ErrorCorrection,
  index: Int,
  acc: List(standard.Encoded),
) -> Result(List(standard.Encoded), EncodeError) {
  case chunks {
    [] -> Ok(list.reverse(acc))
    [chunk, ..rest] -> {
      let parity = parity_of(data)
      let header = build_header(index, total, parity)
      case
        standard.encode_prefixed(chunk, ecc, 1, max_version, None, Auto, header)
      {
        Ok(encoded) ->
          encode_multiple_shards(
            rest,
            data,
            total,
            max_version,
            ecc,
            index + 1,
            [encoded, ..acc],
          )
        Error(error) -> Error(error)
      }
    }
  }
}

fn build_header(index: Int, total: Int, parity: Int) -> BitArray {
  bitstream.new()
  |> bitstream.append_bits(0b0011, size: 4)
  |> bitstream.append_bits(index, size: 4)
  |> bitstream.append_bits(total - 1, size: 4)
  |> bitstream.append_bits(parity, size: 8)
  |> bitstream.to_bit_array
}

fn split_string(data: String, parts: Int) -> List(String) {
  let chars = util.characters(data)
  let total_chars = list.length(chars)
  do_split(chars, parts, total_chars, [])
}

fn do_split(
  chars: List(String),
  remaining_parts: Int,
  remaining_chars: Int,
  acc: List(String),
) -> List(String) {
  case remaining_parts {
    0 -> list.reverse(acc)
    1 -> list.reverse([string.concat(chars), ..acc])
    _ -> {
      let take_count = ceil_div(remaining_chars, remaining_parts)
      let #(taken, rest) = take_chars(chars, take_count, [])
      do_split(rest, remaining_parts - 1, remaining_chars - take_count, [
        string.concat(taken),
        ..acc
      ])
    }
  }
}

fn take_chars(
  chars: List(String),
  count: Int,
  acc: List(String),
) -> #(List(String), List(String)) {
  case chars, count {
    rest, 0 -> #(list.reverse(acc), rest)
    [], _ -> #(list.reverse(acc), [])
    [first, ..rest], _ -> take_chars(rest, count - 1, [first, ..acc])
  }
}

fn ceil_div(numerator: Int, denominator: Int) -> Int {
  case denominator <= 0 {
    True -> numerator
    False -> { numerator + denominator - 1 } / denominator
  }
}
