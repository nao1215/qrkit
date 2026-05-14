//// Reed-Solomon encoder for QR Code codewords.

import gleam/bool
import gleam/int
import gleam/list
import qrkit/internal/util

/// Create a generator polynomial for the requested error-correction degree.
pub fn generator_polynomial(degree: Int) -> List(Int) {
  do_generator_polynomial(degree, [1])
}

fn do_generator_polynomial(degree: Int, polynomial: List(Int)) -> List(Int) {
  use <- bool.guard(when: degree <= 0, return: polynomial)
  let exponent = list.length(polynomial) - 1
  let factor = [1, gf_exp(exponent)]
  do_generator_polynomial(degree - 1, poly_multiply(polynomial, factor))
}

/// Encode `data` and return the error-correction codewords.
pub fn encode(data: List(Int), degree: Int) -> List(Int) {
  let generator = generator_polynomial(degree)
  let padded = list.append(data, util.repeat(0, degree))
  let remainder = poly_mod(padded, generator)
  let padding = util.repeat(0, degree - list.length(remainder))
  list.append(padding, remainder)
}

/// Multiply two field elements in GF(2^8) with primitive polynomial `0x11D`.
pub fn gf_multiply(a: Int, b: Int) -> Int {
  gf_multiply_loop(a, b, 0)
}

pub fn gf_exp(exponent: Int) -> Int {
  gf_exp_loop(normalise_exponent(exponent), 1)
}

fn normalise_exponent(exponent: Int) -> Int {
  case exponent < 0 {
    True -> normalise_exponent(exponent + 255)
    False ->
      case exponent >= 255 {
        True -> normalise_exponent(exponent - 255)
        False -> exponent
      }
  }
}

fn gf_exp_loop(exponent: Int, value: Int) -> Int {
  use <- bool.guard(when: exponent <= 0, return: value)
  let shifted = int.bitwise_shift_left(value, 1)
  let reduced = case int.bitwise_and(shifted, 0x100) != 0 {
    True -> int.bitwise_exclusive_or(shifted, 0x11D)
    False -> shifted
  }
  gf_exp_loop(exponent - 1, int.bitwise_and(reduced, 0xFF))
}

fn gf_multiply_loop(a: Int, b: Int, acc: Int) -> Int {
  use <- bool.guard(when: b == 0, return: acc)
  let next_acc = case int.bitwise_and(b, 1) == 1 {
    True -> int.bitwise_exclusive_or(acc, a)
    False -> acc
  }
  let shifted = int.bitwise_shift_left(a, 1)
  let next_a = case int.bitwise_and(shifted, 0x100) != 0 {
    True -> int.bitwise_exclusive_or(shifted, 0x11D)
    False -> shifted
  }
  gf_multiply_loop(
    int.bitwise_and(next_a, 0xFF),
    int.bitwise_shift_right(b, 1),
    next_acc,
  )
}

fn poly_multiply(left: List(Int), right: List(Int)) -> List(Int) {
  let size = list.length(left) + list.length(right) - 1
  do_poly_multiply(left, right, 0, util.repeat(0, size))
}

fn do_poly_multiply(
  left: List(Int),
  right: List(Int),
  left_index: Int,
  acc: List(Int),
) -> List(Int) {
  case left {
    [] -> acc
    [coefficient, ..rest] -> {
      let next = do_poly_row(right, coefficient, left_index, 0, acc)
      do_poly_multiply(rest, right, left_index + 1, next)
    }
  }
}

fn do_poly_row(
  right: List(Int),
  left_coefficient: Int,
  left_index: Int,
  right_index: Int,
  acc: List(Int),
) -> List(Int) {
  case right {
    [] -> acc
    [coefficient, ..rest] -> {
      let index = left_index + right_index
      let previous = util.at_or(acc, index, default: 0)
      let value =
        int.bitwise_exclusive_or(
          previous,
          gf_multiply(left_coefficient, coefficient),
        )
      do_poly_row(
        rest,
        left_coefficient,
        left_index,
        right_index + 1,
        util.replace_at(acc, index, with: value),
      )
    }
  }
}

fn poly_mod(dividend: List(Int), divisor: List(Int)) -> List(Int) {
  case list.length(dividend) < list.length(divisor) {
    True -> trim_leading_zeros(dividend)
    False -> {
      case dividend {
        [] -> []
        [lead, ..] -> {
          let reduced = do_poly_mod_step(dividend, divisor, lead, 0, [])
          poly_mod(trim_leading_zeros(reduced), divisor)
        }
      }
    }
  }
}

fn do_poly_mod_step(
  dividend: List(Int),
  divisor: List(Int),
  lead: Int,
  index: Int,
  acc: List(Int),
) -> List(Int) {
  case dividend, divisor {
    [left, ..left_rest], [right, ..right_rest] -> {
      let value = int.bitwise_exclusive_or(left, gf_multiply(right, lead))
      do_poly_mod_step(left_rest, right_rest, lead, index + 1, [value, ..acc])
    }
    remaining, [] -> list.reverse(acc) |> list.append(remaining)
    [], _ -> list.reverse(acc)
  }
}

fn trim_leading_zeros(values: List(Int)) -> List(Int) {
  case values {
    [0, ..rest] -> trim_leading_zeros(rest)
    _ -> values
  }
}
