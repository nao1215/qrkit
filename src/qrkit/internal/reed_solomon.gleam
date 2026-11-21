//// Reed-Solomon encoder for QR Code codewords.

import gleam/int
import gleam/list
import qrkit/internal/util

/// alpha^i for i in 0..255 in GF(2^8) with the primitive polynomial `0x11D`
/// (alpha = 2, and alpha^255 = alpha^0).
const exp_table: BitArray = <<
  1, 2, 4, 8, 16, 32, 64, 128, 29, 58, 116, 232, 205, 135, 19, 38, 76, 152, 45,
  90, 180, 117, 234, 201, 143, 3, 6, 12, 24, 48, 96, 192, 157, 39, 78, 156, 37,
  74, 148, 53, 106, 212, 181, 119, 238, 193, 159, 35, 70, 140, 5, 10, 20, 40, 80,
  160, 93, 186, 105, 210, 185, 111, 222, 161, 95, 190, 97, 194, 153, 47, 94, 188,
  101, 202, 137, 15, 30, 60, 120, 240, 253, 231, 211, 187, 107, 214, 177, 127,
  254, 225, 223, 163, 91, 182, 113, 226, 217, 175, 67, 134, 17, 34, 68, 136, 13,
  26, 52, 104, 208, 189, 103, 206, 129, 31, 62, 124, 248, 237, 199, 147, 59, 118,
  236, 197, 151, 51, 102, 204, 133, 23, 46, 92, 184, 109, 218, 169, 79, 158, 33,
  66, 132, 21, 42, 84, 168, 77, 154, 41, 82, 164, 85, 170, 73, 146, 57, 114, 228,
  213, 183, 115, 230, 209, 191, 99, 198, 145, 63, 126, 252, 229, 215, 179, 123,
  246, 241, 255, 227, 219, 171, 75, 150, 49, 98, 196, 149, 55, 110, 220, 165, 87,
  174, 65, 130, 25, 50, 100, 200, 141, 7, 14, 28, 56, 112, 224, 221, 167, 83,
  166, 81, 162, 89, 178, 121, 242, 249, 239, 195, 155, 43, 86, 172, 69, 138, 9,
  18, 36, 72, 144, 61, 122, 244, 245, 247, 243, 251, 235, 203, 139, 11, 22, 44,
  88, 176, 125, 250, 233, 207, 131, 27, 54, 108, 216, 173, 71, 142, 1,
>>

/// log_alpha(v) for v in 1..255; entry 0 is unused.
const log_table: BitArray = <<
  0, 0, 1, 25, 2, 50, 26, 198, 3, 223, 51, 238, 27, 104, 199, 75, 4, 100, 224,
  14, 52, 141, 239, 129, 28, 193, 105, 248, 200, 8, 76, 113, 5, 138, 101, 47,
  225, 36, 15, 33, 53, 147, 142, 218, 240, 18, 130, 69, 29, 181, 194, 125, 106,
  39, 249, 185, 201, 154, 9, 120, 77, 228, 114, 166, 6, 191, 139, 98, 102, 221,
  48, 253, 226, 152, 37, 179, 16, 145, 34, 136, 54, 208, 148, 206, 143, 150, 219,
  189, 241, 210, 19, 92, 131, 56, 70, 64, 30, 66, 182, 163, 195, 72, 126, 110,
  107, 58, 40, 84, 250, 133, 186, 61, 202, 94, 155, 159, 10, 21, 121, 43, 78,
  212, 229, 172, 115, 243, 167, 87, 7, 112, 192, 247, 140, 128, 99, 13, 103, 74,
  222, 237, 49, 197, 254, 24, 227, 165, 153, 119, 38, 184, 180, 124, 17, 68, 146,
  217, 35, 32, 137, 46, 55, 63, 209, 91, 149, 188, 207, 205, 144, 135, 151, 178,
  220, 252, 190, 97, 242, 86, 211, 171, 20, 42, 93, 158, 132, 60, 57, 83, 71,
  109, 65, 162, 31, 45, 67, 216, 183, 123, 164, 118, 196, 23, 73, 236, 127, 12,
  111, 246, 108, 161, 59, 82, 41, 157, 85, 170, 251, 96, 134, 177, 187, 204, 62,
  90, 203, 89, 95, 176, 156, 169, 160, 81, 11, 245, 22, 235, 122, 117, 44, 215,
  79, 174, 213, 233, 230, 231, 173, 232, 116, 214, 244, 234, 168, 80, 88, 175,
>>

/// The generator polynomial (x - alpha^0) .. (x - alpha^(degree - 1)),
/// highest-degree coefficient first.
fn generator_polynomial(degree: Int) -> List(Int) {
  int.range(from: 0, to: degree, with: [1], run: fn(polynomial, i) {
    // polynomial * (x + alpha^i): each coefficient plus alpha^i times the
    // next higher one.
    let root = gf_exp(i)
    list.map2(list.append(polynomial, [0]), [0, ..polynomial], fn(own, higher) {
      int.bitwise_exclusive_or(own, gf_multiply(higher, root))
    })
  })
}

/// Encode `data` and return the error-correction codewords.
pub fn encode(data: List(Int), degree: Int) -> List(Int) {
  remainder(data, generator_polynomial(degree))
}

/// The remainder of `data * x^degree` divided by `generator`, which is
/// monic of degree `degree`: the error-correction codewords, computed one
/// data codeword at a time as a shift register.
fn remainder(data: List(Int), generator: List(Int)) -> List(Int) {
  case generator {
    [] -> []
    [_, ..tail] ->
      list.fold(data, list.repeat(0, list.length(tail)), fn(register, byte) {
        case register {
          [] -> []
          [first, ..rest] -> {
            let shifted = list.append(rest, [0])
            case int.bitwise_exclusive_or(byte, first) {
              0 -> shifted
              factor ->
                list.map2(shifted, tail, fn(value, coefficient) {
                  int.bitwise_exclusive_or(
                    value,
                    gf_multiply(coefficient, factor),
                  )
                })
            }
          }
        }
      })
  }
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
  let generator = generator_polynomial(ec_count)
  let ec_blocks = list.map(data_blocks, remainder(_, generator))
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

/// Read `blocks` column by column, skipping blocks that are exhausted.
fn interleave_lists(blocks: List(List(Int))) -> List(Int) {
  list.transpose(blocks) |> list.flatten
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
    int.range(from: widest - 1, to: -1, with: [], run: fn(acc, column) {
      let owners_in_column =
        list.index_map(sizes, fn(size, block) { #(block, column < size) })
        |> list.filter_map(fn(slot) {
          case slot.1 {
            True -> Ok(slot.0)
            False -> Error(Nil)
          }
        })
      list.append(owners_in_column, acc)
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
        int.range(from: length - 1, to: -1, with: [], run: fn(acc, index) {
          case
            poly_eval_low(locator, gf_exp(255 - { length - 1 - index })) == 0
          {
            True -> [index, ..acc]
            False -> acc
          }
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
  int.range(from: ec_count - 1, to: -1, with: [], run: fn(acc, power) {
    let root = gf_exp(power)
    let syndrome =
      list.fold(block, 0, fn(value, codeword) {
        int.bitwise_exclusive_or(gf_multiply(value, root), codeword)
      })
    [syndrome, ..acc]
  })
}

/// Error locator polynomial, lowest-degree coefficient first.
fn berlekamp_massey(syndromes: List(Int)) -> List(Int) {
  let #(locator, _, length, _, _) =
    list.index_fold(syndromes, #([1], [1], 0, 1, 1), fn(state, _, n) {
      let #(current, previous, length, shift, last_discrepancy) = state
      let discrepancy =
        int.range(from: 0, to: length + 1, with: 0, run: fn(acc, i) {
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
  case value {
    0 -> 0
    _ -> gf_exp(255 - table_at(log_table, value))
  }
}

/// Multiply two field elements in GF(2^8) with primitive polynomial `0x11D`.
fn gf_multiply(a: Int, b: Int) -> Int {
  case a == 0 || b == 0 {
    True -> 0
    False ->
      table_at(
        exp_table,
        { table_at(log_table, a) + table_at(log_table, b) } % 255,
      )
  }
}

/// alpha^exponent for any integer exponent.
fn gf_exp(exponent: Int) -> Int {
  let reduced = exponent % 255
  case reduced < 0 {
    True -> table_at(exp_table, reduced + 255)
    False -> table_at(exp_table, reduced)
  }
}

fn table_at(table: BitArray, index: Int) -> Int {
  case table {
    <<_:bytes-size(index), value, _:bytes>> -> value
    _ -> 0
  }
}
