//// Immutable matrix for QR modules and reserved regions.

import gleam/list
import gleam/option.{type Option, Some}
import gleam/set

pub opaque type Matrix {
  Matrix(width: Int, height: Int, dark: set.Set(Int), reserved: set.Set(Int))
}

/// A finished symbol of any family: its version number, size in modules,
/// data mask and rows of modules (`True` is dark).
pub type Encoded {
  Encoded(
    version: Int,
    width: Int,
    height: Int,
    mask: Int,
    rows: List(List(Bool)),
  )
}

pub fn encoded(
  matrix: Matrix,
  version version: Int,
  mask mask: Int,
) -> Encoded {
  Encoded(version, width(matrix), height(matrix), mask, rows(matrix))
}

pub fn new(width: Int, height: Int) -> Matrix {
  Matrix(width, height, set.new(), set.new())
}

pub fn width(matrix: Matrix) -> Int {
  let Matrix(width, _, _, _) = matrix
  width
}

pub fn height(matrix: Matrix) -> Int {
  let Matrix(_, height, _, _) = matrix
  height
}

pub fn set(
  matrix: Matrix,
  row: Int,
  col: Int,
  value: Bool,
  reserved is_reserved: Bool,
) -> Matrix {
  let Matrix(width, height, dark, reserved) = matrix
  let index = row * width + col
  let next_dark = case value {
    True -> set.insert(dark, index)
    False -> set.delete(dark, index)
  }
  let next_reserved = case is_reserved {
    True -> set.insert(reserved, index)
    False -> reserved
  }
  Matrix(width, height, next_dark, next_reserved)
}

pub fn get(matrix: Matrix, row: Int, col: Int) -> Bool {
  let Matrix(width, _, dark, _) = matrix
  set.contains(dark, row * width + col)
}

pub fn xor(matrix: Matrix, row: Int, col: Int, value: Bool) -> Matrix {
  case value {
    False -> matrix
    True ->
      set(
        matrix,
        row,
        col,
        !get(matrix, row, col),
        reserved: is_reserved(matrix, row, col),
      )
  }
}

pub fn is_reserved(matrix: Matrix, row: Int, col: Int) -> Bool {
  let Matrix(width, _, _, reserved) = matrix
  set.contains(reserved, row * width + col)
}

pub fn dark_count(matrix: Matrix) -> Int {
  let Matrix(_, _, dark, _) = matrix
  set.size(dark)
}

pub fn total_cells(matrix: Matrix) -> Int {
  width(matrix) * height(matrix)
}

fn rows(matrix: Matrix) -> List(List(Bool)) {
  build_rows(matrix, 0, [])
}

fn build_rows(
  matrix: Matrix,
  row: Int,
  acc: List(List(Bool)),
) -> List(List(Bool)) {
  case row >= height(matrix) {
    True -> list.reverse(acc)
    False -> build_rows(matrix, row + 1, [build_row(matrix, row, 0, []), ..acc])
  }
}

fn build_row(
  matrix: Matrix,
  row: Int,
  col: Int,
  acc: List(Bool),
) -> List(Bool) {
  case col >= width(matrix) {
    True -> list.reverse(acc)
    False -> build_row(matrix, row, col + 1, [get(matrix, row, col), ..acc])
  }
}

/// The `(row, col)` of every module that is not reserved, in the order
/// Standard QR and Micro QR place codeword bits: column pairs from the right
/// edge, upward then downward in turn, right module before left.
/// `skip_column` names a column that is never part of a pair (the vertical
/// timing pattern of Standard QR).
pub fn data_positions(
  matrix: Matrix,
  skip_column skip_column: Option(Int),
) -> List(#(Int, Int)) {
  data_positions_loop(
    matrix,
    skip_column,
    width(matrix) - 1,
    height(matrix) - 1,
    -1,
    [],
  )
}

fn data_positions_loop(
  matrix: Matrix,
  skip_column: Option(Int),
  col: Int,
  row: Int,
  inc: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case col <= 0 {
    True -> list.reverse(acc)
    False -> {
      let actual_col = case Some(col) == skip_column {
        True -> col - 1
        False -> col
      }
      let #(next_acc, next_row, next_inc) =
        scan_column_pair(matrix, actual_col, row, inc, acc)
      data_positions_loop(
        matrix,
        skip_column,
        actual_col - 2,
        next_row,
        next_inc,
        next_acc,
      )
    }
  }
}

fn scan_column_pair(
  matrix: Matrix,
  col: Int,
  row: Int,
  inc: Int,
  acc: List(#(Int, Int)),
) -> #(List(#(Int, Int)), Int, Int) {
  let with_right = take_if_data(matrix, row, col, acc)
  let with_both = take_if_data(matrix, row, col - 1, with_right)
  let next_row = row + inc
  case next_row < 0 || next_row >= height(matrix) {
    True -> #(with_both, row, 0 - inc)
    False -> scan_column_pair(matrix, col, next_row, inc, with_both)
  }
}

fn take_if_data(
  matrix: Matrix,
  row: Int,
  col: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case is_reserved(matrix, row, col) {
    True -> acc
    False -> [#(row, col), ..acc]
  }
}

/// Set the module at each position to the matching bit, as data (not
/// reserved). Stops when either list runs out: positions left over keep
/// their light default, which is what the remainder bits need.
pub fn write_bits(
  matrix: Matrix,
  positions: List(#(Int, Int)),
  bits: List(Bool),
) -> Matrix {
  case positions, bits {
    [#(row, col), ..rest_positions], [bit, ..rest_bits] ->
      write_bits(
        set(matrix, row, col, bit, reserved: False),
        rest_positions,
        rest_bits,
      )
    _, _ -> matrix
  }
}
