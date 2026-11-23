//// Standard QR data masks and penalty scoring.

import gleam/int
import gleam/list
import qrkit/internal/matrix
import qrkit/internal/util

/// Apply Standard QR data mask `mask` (0..7) to every module that is not
/// reserved.
pub fn apply(mask: Int, to target: matrix.Matrix) -> matrix.Matrix {
  apply_with(target, fn(row, col) { mask_at(mask, row, col) })
}

/// Flip every module that is not reserved and for which `flip(row, col)`
/// holds. Micro QR and rMQR pass their own mask patterns.
pub fn apply_with(
  target: matrix.Matrix,
  flip: fn(Int, Int) -> Bool,
) -> matrix.Matrix {
  apply_loop(target, flip, 0, 0)
}

fn apply_loop(
  target: matrix.Matrix,
  flip: fn(Int, Int) -> Bool,
  row: Int,
  col: Int,
) -> matrix.Matrix {
  case row >= matrix.height(target) {
    True -> target
    False ->
      case col >= matrix.width(target) {
        True -> apply_loop(target, flip, row + 1, 0)
        False ->
          case matrix.is_reserved(target, row, col) {
            True -> apply_loop(target, flip, row, col + 1)
            False ->
              apply_loop(
                matrix.xor(target, row, col, flip(row, col)),
                flip,
                row,
                col + 1,
              )
          }
      }
  }
}

/// The ISO/IEC 18004 §7.8.3 penalty of a square Standard QR symbol. The
/// rows and columns are read once and shared by the first three rules.
pub fn penalty_total(target: matrix.Matrix) -> Int {
  let rows = matrix.rows(target)
  let columns = list.transpose(rows)
  penalty_n1(rows, columns)
  + penalty_n2(rows)
  + penalty_n3(rows, columns)
  + penalty_n4(target)
}

/// Runs of five or more same-coloured modules in a row or column.
fn penalty_n1(rows: List(List(Bool)), columns: List(List(Bool))) -> Int {
  sum_lines(rows, line_penalty) + sum_lines(columns, line_penalty)
}

fn sum_lines(lines: List(List(Bool)), score: fn(List(Bool)) -> Int) -> Int {
  list.fold(lines, 0, fn(acc, line) { acc + score(line) })
}

fn line_penalty(values: List(Bool)) -> Int {
  case values {
    [] -> 0
    [first, ..rest] -> line_penalty_loop(rest, first, 1, 0)
  }
}

fn line_penalty_loop(
  values: List(Bool),
  last: Bool,
  run_length: Int,
  penalty: Int,
) -> Int {
  case values {
    [] -> penalty + run_penalty(run_length)
    [value, ..rest] ->
      case value == last {
        True -> line_penalty_loop(rest, last, run_length + 1, penalty)
        False ->
          line_penalty_loop(rest, value, 1, penalty + run_penalty(run_length))
      }
  }
}

fn run_penalty(run_length: Int) -> Int {
  case run_length >= 5 {
    True -> 3 + run_length - 5
    False -> 0
  }
}

/// 2x2 blocks of one colour.
fn penalty_n2(rows: List(List(Bool))) -> Int {
  penalty_n2_loop(rows, 0) * 3
}

fn penalty_n2_loop(rows: List(List(Bool)), acc: Int) -> Int {
  case rows {
    [top, bottom, ..rest] ->
      penalty_n2_loop([bottom, ..rest], same_colour_blocks(top, bottom, acc))
    _ -> acc
  }
}

fn same_colour_blocks(top: List(Bool), bottom: List(Bool), acc: Int) -> Int {
  case top, bottom {
    [a, b, ..top_rest], [c, d, ..bottom_rest] -> {
      let next_acc = case a == b && b == c && c == d {
        True -> acc + 1
        False -> acc
      }
      same_colour_blocks([b, ..top_rest], [d, ..bottom_rest], next_acc)
    }
    _, _ -> acc
  }
}

/// The 1:1:3:1:1 finder-like pattern `1011101` with four light modules
/// before or after it. The quiet zone around the symbol is light, so the
/// light modules may lie outside the symbol. Each occurrence of the pattern
/// counts once, as in ISO/IEC 18004 §7.8.3.1 Table 11, zxing and segno.
fn penalty_n3(rows: List(List(Bool)), columns: List(List(Bool))) -> Int {
  { sum_lines(rows, finder_like_count) + sum_lines(columns, finder_like_count) }
  * 40
}

const quiet: List(Bool) = [False, False, False, False]

fn finder_like_count(values: List(Bool)) -> Int {
  finder_like_loop(list.flatten([quiet, values, quiet]), 0, 0, 0)
}

// `window` holds the last 15 modules: four before the pattern, the seven
// pattern modules and four after it.
fn finder_like_loop(
  values: List(Bool),
  window: Int,
  seen: Int,
  count: Int,
) -> Int {
  case values {
    [] -> count
    [value, ..rest] -> {
      let window = int.bitwise_and(window * 2 + util.bool_to_int(value), 0x7FFF)
      let seen = seen + 1
      let pattern = int.bitwise_and(int.bitwise_shift_right(window, 4), 0x7F)
      let light_before = int.bitwise_shift_right(window, 11) == 0
      let light_after = int.bitwise_and(window, 0xF) == 0
      let count = case
        seen >= 15 && pattern == 0x5D && { light_before || light_after }
      {
        True -> count + 1
        False -> count
      }
      finder_like_loop(rest, window, seen, count)
    }
  }
}

/// Ten points for each full 5% step that the dark proportion lies away from
/// 50%. `|100 * dark / total - 50| / 5` is computed exactly, as
/// `|20 * dark - 10 * total| / total`, so 45.1% dark scores 0.
fn penalty_n4(target: matrix.Matrix) -> Int {
  let dark = matrix.dark_count(target)
  let total = matrix.total_cells(target)
  int.absolute_value(20 * dark - 10 * total) / total * 10
}

pub fn mask_at(mask: Int, row: Int, col: Int) -> Bool {
  case mask {
    0 -> { row + col } % 2 == 0
    1 -> row % 2 == 0
    2 -> col % 3 == 0
    3 -> { row + col } % 3 == 0
    4 -> { row / 2 + col / 3 } % 2 == 0
    5 -> { row * col % 2 + row * col % 3 } == 0
    6 -> { row * col % 2 + row * col % 3 } % 2 == 0
    _ -> { row * col % 3 + { row + col } % 2 } % 2 == 0
  }
}
