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

/// Split `data` into `blocks` error-correction blocks, add each block's
/// error-correction codewords, and interleave the result for placement.
///
/// ISO/IEC 18004 and ISO/IEC 23941 use the same block layout: every block
/// has the same number of error-correction codewords, and when the data does
/// not divide evenly the last `total_codewords % blocks` blocks carry one
/// extra data codeword. Data codewords are interleaved column by column
/// (shorter blocks are skipped once exhausted), followed by the
/// error-correction codewords in the same order.
pub fn encode_interleaved(
  data: List(Int),
  total_codewords total_codewords: Int,
  blocks blocks: Int,
) -> List(Int) {
  let data_codewords = list.length(data)
  let blocks_in_group2 = total_codewords % blocks
  let blocks_in_group1 = blocks - blocks_in_group2
  let data_codewords_in_group1 = data_codewords / blocks
  let ec_count = total_codewords / blocks - data_codewords_in_group1
  let data_blocks =
    split_into_blocks(
      data,
      blocks_in_group1,
      data_codewords_in_group1,
      blocks_in_group2,
      data_codewords_in_group1 + 1,
      [],
    )
  let ec_blocks = list.map(data_blocks, fn(block) { encode(block, ec_count) })
  list.append(interleave_lists(data_blocks), interleave_lists(ec_blocks))
}

fn split_into_blocks(
  bytes: List(Int),
  group1_count: Int,
  group1_size: Int,
  group2_count: Int,
  group2_size: Int,
  acc: List(List(Int)),
) -> List(List(Int)) {
  case group1_count > 0, group2_count > 0 {
    True, _ -> {
      let #(head, tail) = list.split(bytes, group1_size)
      split_into_blocks(
        tail,
        group1_count - 1,
        group1_size,
        group2_count,
        group2_size,
        [head, ..acc],
      )
    }
    False, True -> {
      let #(head, tail) = list.split(bytes, group2_size)
      split_into_blocks(
        tail,
        group1_count,
        group1_size,
        group2_count - 1,
        group2_size,
        [head, ..acc],
      )
    }
    False, False -> list.reverse(acc)
  }
}

fn interleave_lists(blocks: List(List(Int))) -> List(Int) {
  let width =
    list.fold(blocks, 0, fn(widest, block) {
      int.max(widest, list.length(block))
    })
  util.range(0, width - 1)
  |> list.flat_map(fn(index) {
    list.filter_map(blocks, fn(block) { util.at(block, index) })
  })
}

/// Undo `encode_interleaved`: split the codewords read from a symbol into its
/// blocks, each holding its data codewords followed by its error-correction
/// codewords.
pub fn deinterleave(
  codewords: List(Int),
  total_codewords total_codewords: Int,
  data_codewords data_codewords: Int,
  blocks blocks: Int,
) -> List(List(Int)) {
  let blocks_in_group2 = total_codewords % blocks
  let data1 = data_codewords / blocks
  let ec_count = total_codewords / blocks - data1
  let sizes =
    list.append(
      list.repeat(data1, blocks - blocks_in_group2),
      list.repeat(data1 + 1, blocks_in_group2),
    )
  let #(data_part, ec_part) = list.split(codewords, data_codewords)
  let data_blocks = distribute(data_part, sizes)
  let ec_blocks = distribute(ec_part, list.repeat(ec_count, blocks))
  list.map2(data_blocks, ec_blocks, list.append)
}

/// Hand codewords out column by column to blocks of the given sizes, skipping
/// blocks that are already full.
fn distribute(codewords: List(Int), sizes: List(Int)) -> List(List(Int)) {
  let widest = list.fold(sizes, 0, int.max)
  let owners =
    util.range(0, widest - 1)
    |> list.flat_map(fn(column) {
      list.index_map(sizes, fn(size, block) { #(block, column < size) })
      |> list.filter_map(fn(slot) {
        case slot.1 {
          True -> Ok(slot.0)
          False -> Error(Nil)
        }
      })
    })
  let tagged = list.zip(owners, codewords)
  list.index_map(sizes, fn(_, block) {
    list.filter_map(tagged, fn(entry) {
      case entry.0 == block {
        True -> Ok(entry.1)
        False -> Error(Nil)
      }
    })
  })
}

/// Correct a received block (data then `ec_count` error-correction
/// codewords) and return it with the number of codewords changed. Uses
/// Berlekamp-Massey for the error locator, a Chien search for the positions
/// and Forney's formula for the values. Fails when the block has more errors
/// than the code can locate consistently.
pub fn correct(
  block: List(Int),
  ec_count: Int,
) -> Result(#(List(Int), Int), Nil) {
  let received = syndromes(block, ec_count)
  case list.all(received, fn(value) { value == 0 }) {
    True -> Ok(#(block, 0))
    False -> {
      let locator = berlekamp_massey(received)
      let errors = list.length(locator) - 1
      let length = list.length(block)
      let positions =
        util.range(0, length - 1)
        |> list.filter(fn(index) {
          poly_eval_low(locator, gf_exp(255 - { length - 1 - index })) == 0
        })
      case errors * 2 > ec_count || list.length(positions) != errors {
        True -> Error(Nil)
        False -> {
          let evaluator =
            poly_multiply_low(received, locator) |> list.take(ec_count)
          let derivative = formal_derivative(locator)
          let corrected =
            list.index_map(block, fn(codeword, index) {
              case list.contains(positions, index) {
                False -> codeword
                True -> {
                  let x = gf_exp(length - 1 - index)
                  let x_inverse = gf_exp(255 - { length - 1 - index })
                  let magnitude =
                    gf_multiply(
                      gf_multiply(x, poly_eval_low(evaluator, x_inverse)),
                      gf_inverse(poly_eval_low(derivative, x_inverse)),
                    )
                  int.bitwise_exclusive_or(codeword, magnitude)
                }
              }
            })
          case list.all(syndromes(corrected, ec_count), fn(v) { v == 0 }) {
            True -> Ok(#(corrected, errors))
            False -> Error(Nil)
          }
        }
      }
    }
  }
}

/// S_i = r(alpha^i) for i in 0 .. ec_count - 1, reading the block as a
/// polynomial with its first codeword as the highest-degree coefficient.
fn syndromes(block: List(Int), ec_count: Int) -> List(Int) {
  util.range(0, ec_count - 1)
  |> list.map(fn(power) {
    let root = gf_exp(power)
    list.fold(block, 0, fn(acc, codeword) {
      int.bitwise_exclusive_or(gf_multiply(acc, root), codeword)
    })
  })
}

/// Error locator polynomial, lowest-degree coefficient first.
fn berlekamp_massey(syndromes: List(Int)) -> List(Int) {
  let #(locator, _, length, _, _) =
    list.index_fold(syndromes, #([1], [1], 0, 1, 1), fn(state, _, n) {
      let #(current, previous, length, shift, last_discrepancy) = state
      let discrepancy =
        util.range(0, length)
        |> list.fold(0, fn(acc, i) {
          int.bitwise_exclusive_or(
            acc,
            gf_multiply(
              util.at_or(current, i, default: 0),
              util.at_or(syndromes, n - i, default: 0),
            ),
          )
        })
      case discrepancy == 0 {
        True -> #(current, previous, length, shift + 1, last_discrepancy)
        False -> {
          let scale = gf_multiply(discrepancy, gf_inverse(last_discrepancy))
          let adjusted =
            poly_add_low(
              current,
              list.append(
                list.repeat(0, shift),
                list.map(previous, fn(c) { gf_multiply(c, scale) }),
              ),
            )
          case 2 * length <= n {
            True -> #(adjusted, current, n + 1 - length, 1, discrepancy)
            False -> #(adjusted, previous, length, shift + 1, last_discrepancy)
          }
        }
      }
    })
  list.take(locator, length + 1)
}

fn poly_add_low(left: List(Int), right: List(Int)) -> List(Int) {
  case left, right {
    [], rest | rest, [] -> rest
    [a, ..left_rest], [b, ..right_rest] -> [
      int.bitwise_exclusive_or(a, b),
      ..poly_add_low(left_rest, right_rest)
    ]
  }
}

fn poly_multiply_low(left: List(Int), right: List(Int)) -> List(Int) {
  list.index_fold(left, [], fn(acc, a, i) {
    poly_add_low(
      acc,
      list.append(
        list.repeat(0, i),
        list.map(right, fn(b) { gf_multiply(a, b) }),
      ),
    )
  })
}

fn poly_eval_low(poly: List(Int), x: Int) -> Int {
  list.fold_right(poly, 0, fn(acc, coefficient) {
    int.bitwise_exclusive_or(gf_multiply(acc, x), coefficient)
  })
}

/// Formal derivative over GF(2^8): only odd-degree terms survive.
fn formal_derivative(poly: List(Int)) -> List(Int) {
  case poly {
    [] -> []
    [_, ..rest] ->
      list.index_map(rest, fn(coefficient, i) {
        case i % 2 == 0 {
          True -> coefficient
          False -> 0
        }
      })
  }
}

fn gf_inverse(value: Int) -> Int {
  // value^254 = value^-1 in GF(2^8).
  gf_power(value, 254, 1)
}

fn gf_power(base: Int, exponent: Int, acc: Int) -> Int {
  case exponent {
    0 -> acc
    _ -> {
      let next_acc = case exponent % 2 == 1 {
        True -> gf_multiply(acc, base)
        False -> acc
      }
      gf_power(gf_multiply(base, base), exponent / 2, next_acc)
    }
  }
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
