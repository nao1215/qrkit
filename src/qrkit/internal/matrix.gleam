//// Immutable matrix for QR modules and reserved regions.

import gleam/list
import gleam/set
import qrkit/internal/util

pub opaque type Matrix {
  Matrix(width: Int, height: Int, dark: set.Set(Int), reserved: set.Set(Int))
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

pub fn rows(matrix: Matrix) -> List(List(Bool)) {
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

fn build_row(matrix: Matrix, row: Int, col: Int, acc: List(Bool)) -> List(Bool) {
  case col >= width(matrix) {
    True -> list.reverse(acc)
    False -> build_row(matrix, row, col + 1, [get(matrix, row, col), ..acc])
  }
}

pub fn positions(matrix: Matrix) -> List(#(Int, Int)) {
  util.range(0, height(matrix) - 1)
  |> list.flat_map(fn(row) {
    util.range(0, width(matrix) - 1)
    |> list.map(fn(col) { #(row, col) })
  })
}
