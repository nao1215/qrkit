//// Regression test: rMQR symbols whose error correction is split into
//// several Reed-Solomon blocks (ISO/IEC 23941:2022 Table 8) must carry
//// one valid Reed-Solomon codeword per block. The encoder used to compute
//// a single block over all data codewords, which produced symbols that
//// zxing-cpp could not read for 35 of the 64 version/level pairs.
////
//// The check reads the codewords back from `qrkit.rows` in the module
//// order a reader uses (zxing-cpp's ReadRMQRCodewords with its rMQR
//// function pattern), splits them into the blocks Table 8 defines, and
//// requires every block's syndromes to be zero. The function pattern and
//// the block table are written out here independently of the encoder.

import gleam/int
import gleam/list
import gleeunit/should
import qrkit
import qrkit/internal/reed_solomon
import qrkit/types

/// ISO/IEC 23941:2022 Table 8, per version R7x43 .. R17x139:
/// #(blocks in group 1, data codewords per group-1 block,
///   blocks in group 2, data codewords per group-2 block).
const table8_m: List(#(Int, Int, Int, Int)) = [
  #(1, 6, 0, 0),
  #(1, 12, 0, 0),
  #(1, 20, 0, 0),
  #(1, 28, 0, 0),
  #(1, 44, 0, 0),
  #(1, 12, 0, 0),
  #(1, 21, 0, 0),
  #(1, 31, 0, 0),
  #(1, 42, 0, 0),
  #(1, 31, 1, 32),
  #(1, 7, 0, 0),
  #(1, 19, 0, 0),
  #(1, 31, 0, 0),
  #(1, 43, 0, 0),
  #(1, 28, 1, 29),
  #(2, 42, 0, 0),
  #(1, 12, 0, 0),
  #(1, 27, 0, 0),
  #(1, 38, 0, 0),
  #(1, 26, 1, 27),
  #(1, 36, 1, 37),
  #(2, 35, 1, 36),
  #(1, 33, 0, 0),
  #(1, 48, 0, 0),
  #(1, 33, 1, 34),
  #(2, 44, 0, 0),
  #(2, 42, 1, 43),
  #(1, 39, 0, 0),
  #(2, 28, 0, 0),
  #(2, 39, 0, 0),
  #(2, 33, 1, 34),
  #(4, 38, 0, 0),
]

const table8_h: List(#(Int, Int, Int, Int)) = [
  #(1, 3, 0, 0),
  #(1, 7, 0, 0),
  #(1, 10, 0, 0),
  #(1, 14, 0, 0),
  #(2, 12, 0, 0),
  #(1, 7, 0, 0),
  #(1, 11, 0, 0),
  #(1, 8, 1, 9),
  #(2, 11, 0, 0),
  #(3, 11, 0, 0),
  #(1, 5, 0, 0),
  #(1, 11, 0, 0),
  #(1, 7, 1, 8),
  #(1, 11, 1, 12),
  #(1, 14, 1, 15),
  #(3, 14, 0, 0),
  #(1, 7, 0, 0),
  #(1, 13, 0, 0),
  #(2, 10, 0, 0),
  #(1, 14, 1, 15),
  #(1, 11, 2, 12),
  #(2, 13, 2, 14),
  #(1, 7, 1, 8),
  #(2, 13, 0, 0),
  #(2, 10, 1, 11),
  #(4, 12, 0, 0),
  #(1, 13, 4, 14),
  #(1, 10, 1, 11),
  #(2, 14, 0, 0),
  #(1, 12, 2, 13),
  #(4, 14, 0, 0),
  #(2, 12, 4, 13),
]

/// Alignment pattern centre columns per symbol width, ISO/IEC 23941 Table D.1.
fn alignment_columns(width: Int) -> List(Int) {
  case width {
    43 -> [21]
    59 -> [19, 39]
    77 -> [25, 51]
    99 -> [23, 49, 75]
    139 -> [27, 55, 83, 111]
    _ -> []
  }
}

pub fn every_rmqr_version_has_valid_reed_solomon_blocks_test() -> Nil {
  let checked =
    list.flatten([
      list.index_map(table8_m, fn(layout, index) {
        check_symbol(index + 1, types.Medium, layout)
      }),
      list.index_map(table8_h, fn(layout, index) {
        check_symbol(index + 1, types.High, layout)
      }),
    ])
  // Every version/level pair is exercised, and none of them fails.
  list.length(checked) |> should.equal(64)
  list.filter(checked, fn(entry) { !entry.1 })
  |> should.equal([])
}

fn check_symbol(
  version: Int,
  ecc: types.ErrorCorrection,
  layout: #(Int, Int, Int, Int),
) -> #(#(Int, types.ErrorCorrection), Bool) {
  let assert Ok(qr) =
    qrkit.new("ab")
    |> qrkit.with_symbol(types.Rectangular)
    |> qrkit.with_ecc(ecc)
    |> qrkit.with_exact_version(version)
    |> qrkit.with_mode_preference(types.ForceByte)
    |> qrkit.build
  let codewords = read_codewords(qrkit.rows(qr))
  #(#(version, ecc), blocks_are_valid(codewords, layout))
}

fn blocks_are_valid(
  codewords: List(Int),
  layout: #(Int, Int, Int, Int),
) -> Bool {
  let #(group1, data1, group2, data2) = layout
  let block_count = group1 + group2
  let sizes =
    list.append(list.repeat(data1, group1), list.repeat(data2, group2))
  let data_total = group1 * data1 + group2 * data2
  let ec_per_block = { list.length(codewords) - data_total } / block_count
  let #(data_part, ec_part) = list.split(codewords, data_total)
  let data_blocks = deinterleave(data_part, sizes)
  let ec_blocks = deinterleave(ec_part, list.repeat(ec_per_block, block_count))
  list.length(codewords) - data_total == ec_per_block * block_count
  && list.all(list.zip(data_blocks, ec_blocks), fn(pair) {
    syndromes_are_zero(list.append(pair.0, pair.1), ec_per_block)
  })
}

/// Undo the column-by-column interleaving: codeword `i` of every block that
/// is long enough, block by block, for i = 0, 1, ...
fn deinterleave(codewords: List(Int), sizes: List(Int)) -> List(List(Int)) {
  let widest = list.fold(sizes, 0, int.max)
  let slots =
    int.range(from: 0, to: widest, with: [], run: fn(acc, column) {
      list.index_fold(sizes, acc, fn(acc2, size, block) {
        case column < size {
          True -> [block, ..acc2]
          False -> acc2
        }
      })
    })
    |> list.reverse
  let owners = list.zip(slots, codewords)
  list.index_map(sizes, fn(_, block) {
    list.filter_map(owners, fn(owner) {
      case owner.0 == block {
        True -> Ok(owner.1)
        False -> Error(Nil)
      }
    })
  })
}

/// A block is a valid codeword of the QR Reed-Solomon code when it evaluates
/// to zero at alpha^0 .. alpha^(ec - 1).
fn syndromes_are_zero(block: List(Int), ec_count: Int) -> Bool {
  int.range(from: 0, to: ec_count, with: True, run: fn(ok, power) {
    let root = reed_solomon.gf_exp(power)
    ok
    && list.fold(block, 0, fn(acc, codeword) {
      int.bitwise_exclusive_or(reed_solomon.gf_multiply(acc, root), codeword)
    })
    == 0
  })
}

/// Read codewords the way a reader does: column pairs from the right edge
/// (skipping the rightmost timing column), alternating upward and downward,
/// skipping function-pattern modules and removing the fixed rMQR mask.
fn read_codewords(rows: List(List(Bool))) -> List(Int) {
  let height = list.length(rows)
  let assert [first, ..] = rows
  let width = list.length(first)
  let bits =
    column_pairs(width - 2, [])
    |> list.index_map(fn(x, pair_index) {
      list.flat_map(scan_rows(pair_index, height), fn(y) {
        [x, x - 1]
        |> list.filter(fn(xx) { !is_function(xx, y, width, height) })
        |> list.map(fn(xx) {
          let mask = { y / 2 + xx / 3 } % 2 == 0
          mask != module_at(rows, xx, y)
        })
      })
    })
    |> list.flatten
  to_bytes(bits, 0, 0, [])
}

/// Rows of a column pair in reading order: upward for the first pair from
/// the right, then alternating.
fn scan_rows(pair_index: Int, height: Int) -> List(Int) {
  let downward =
    int.range(from: 0, to: height, with: [], run: fn(acc, y) { [y, ..acc] })
    |> list.reverse
  case pair_index % 2 == 0 {
    True -> list.reverse(downward)
    False -> downward
  }
}

fn module_at(rows: List(List(Bool)), x: Int, y: Int) -> Bool {
  let assert Ok(row) = list.drop(rows, y) |> list.first
  let assert Ok(bit) = list.drop(row, x) |> list.first
  bit
}

fn column_pairs(x: Int, acc: List(Int)) -> List(Int) {
  case x > 0 {
    True -> column_pairs(x - 2, [x, ..acc])
    False -> list.reverse(acc)
  }
}

fn to_bytes(
  bits: List(Bool),
  current: Int,
  count: Int,
  acc: List(Int),
) -> List(Int) {
  case bits {
    [] -> list.reverse(acc)
    [bit, ..rest] -> {
      let value =
        current
        * 2
        + case bit {
          True -> 1
          False -> 0
        }
      case count == 7 {
        True -> to_bytes(rest, 0, 0, [value, ..acc])
        False -> to_bytes(rest, value, count + 1, acc)
      }
    }
  }
}

/// rMQR function pattern (zxing-cpp Version::buildFunctionPattern).
fn is_function(x: Int, y: Int, width: Int, height: Int) -> Bool {
  let in_region = fn(x0, y0, dx, dy) {
    x >= x0 && x < x0 + dx && y >= y0 && y < y0 + dy
  }
  let finder_height = case height == 7 {
    True -> 6
    False -> 7
  }
  y == 0
  || y == height - 1
  || x == 0
  || x == width - 1
  || list.any(alignment_columns(width), fn(cx) {
    in_region(cx - 1, 1, 3, 2)
    || in_region(cx - 1, height - 3, 3, 2)
    || in_region(cx, 3, 1, height - 6)
  })
  || in_region(1, 1, 7, finder_height)
  || in_region(8, 1, 3, 5)
  || in_region(11, 1, 1, 3)
  || in_region(width - 5, height - 5, 4, 4)
  || in_region(width - 8, height - 6, 3, 5)
  || in_region(width - 5, height - 6, 3, 1)
  || { x == width - 2 && y == 1 }
  || { height > 9 && x == 1 && y == height - 2 }
}
