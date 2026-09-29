//// BCH encoding for standard QR format and version information.

import gleam/int
import gleam/list
import qrkit/types.{type ErrorCorrection, High, Low, Medium, Quartile}

const g15 = 0b10100110111

const g15_mask = 0b101010000010010

const g18 = 0b1111100100101

pub fn format_bits(ecc: ErrorCorrection, mask: Int) -> Int {
  let data = int_from_ecc(ecc) * 8 + mask
  let remainder = bch_remainder(data, g15, 10)
  int.bitwise_exclusive_or(data * 1024 + remainder, g15_mask)
}

/// The error correction level and mask whose format information is nearest
/// to either copy, if it is within 3 bits (the BCH(15,5) code corrects up to
/// three errors).
pub fn decode_format(
  first: Int,
  second: Int,
) -> Result(#(ErrorCorrection, Int), Nil) {
  let candidates =
    list.flat_map([Low, Medium, Quartile, High], fn(ecc) {
      list.map([0, 1, 2, 3, 4, 5, 6, 7], fn(mask) {
        #(#(ecc, mask), format_bits(ecc, mask))
      })
    })
  nearest(candidates, [first, second], 3)
}

/// The value of the candidate nearest (by Hamming distance) to any of
/// `readings`, when that distance is at most `limit`.
pub fn nearest(
  candidates: List(#(a, Int)),
  readings: List(Int),
  limit: Int,
) -> Result(a, Nil) {
  let best =
    list.fold(candidates, #(Error(Nil), limit + 1), fn(best, candidate) {
      let distance =
        list.fold(readings, limit + 1, fn(closest, reading) {
          int.min(closest, hamming(candidate.1, reading))
        })
      case distance < best.1 {
        True -> #(Ok(candidate.0), distance)
        False -> best
      }
    })
  best.0
}

fn hamming(left: Int, right: Int) -> Int {
  count_ones(int.bitwise_exclusive_or(left, right), 0)
}

fn count_ones(value: Int, acc: Int) -> Int {
  case value == 0 {
    True -> acc
    False ->
      count_ones(
        int.bitwise_shift_right(value, 1),
        acc + int.bitwise_and(value, 1),
      )
  }
}

pub fn version_bits(version: Int) -> Int {
  let remainder = bch_remainder(version, g18, 12)
  version * 4096 + remainder
}

fn bch_remainder(value: Int, polynomial: Int, shift: Int) -> Int {
  do_bch_remainder(value * power_of_two(shift), polynomial)
}

fn do_bch_remainder(value: Int, polynomial: Int) -> Int {
  case bit_length(value) < bit_length(polynomial) {
    True -> value
    False ->
      do_bch_remainder(
        int.bitwise_exclusive_or(
          value,
          polynomial * power_of_two(bit_length(value) - bit_length(polynomial)),
        ),
        polynomial,
      )
  }
}

fn bit_length(value: Int) -> Int {
  case value == 0 {
    True -> 0
    False -> 1 + bit_length(int.bitwise_shift_right(value, 1))
  }
}

fn power_of_two(value: Int) -> Int {
  case value <= 0 {
    True -> 1
    False -> 2 * power_of_two(value - 1)
  }
}

fn int_from_ecc(ecc: ErrorCorrection) -> Int {
  case ecc {
    Low -> 1
    Medium -> 0
    Quartile -> 3
    High -> 2
  }
}
