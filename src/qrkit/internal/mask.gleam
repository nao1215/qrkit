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

pub fn penalty_total(target: matrix.Matrix) -> Int {
  penalty_n1(target)
  + penalty_n2(target)
  + penalty_n3(target)
  + penalty_n4(target)
}

fn penalty_n1(target: matrix.Matrix) -> Int {
  penalty_runs(target, 0, 0, 0)
}

fn penalty_runs(
  target: matrix.Matrix,
  row: Int,
  col_points: Int,
  row_points: Int,
) -> Int {
  case row >= matrix.height(target) {
    True -> col_points + row_points
    False ->
      penalty_runs(
        target,
        row + 1,
        col_points + line_penalty(column_values(target, row)),
        row_points + line_penalty(row_values(target, row)),
      )
  }
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

fn penalty_n2(target: matrix.Matrix) -> Int {
  do_penalty_n2(target, 0, 0, 0)
}

fn do_penalty_n2(target: matrix.Matrix, row: Int, col: Int, acc: Int) -> Int {
  case row >= matrix.height(target) - 1 {
    True -> acc * 3
    False ->
      case col >= matrix.width(target) - 1 {
        True -> do_penalty_n2(target, row + 1, 0, acc)
        False -> {
          let dark_total =
            util.bool_to_int(matrix.get(target, row, col))
            + util.bool_to_int(matrix.get(target, row, col + 1))
            + util.bool_to_int(matrix.get(target, row + 1, col))
            + util.bool_to_int(matrix.get(target, row + 1, col + 1))
          let next_acc = case dark_total == 0 || dark_total == 4 {
            True -> acc + 1
            False -> acc
          }
          do_penalty_n2(target, row, col + 1, next_acc)
        }
      }
  }
}

fn penalty_n3(target: matrix.Matrix) -> Int {
  let rows =
    int.range(from: 0, to: matrix.height(target), with: 0, run: fn(acc, row) {
      acc + finder_like_penalty(row_values(target, row))
    })
  let columns =
    int.range(from: 0, to: matrix.width(target), with: 0, run: fn(acc, col) {
      acc + finder_like_penalty(column_values(target, col))
    })
  { rows + columns } * 40
}

fn finder_like_penalty(values: List(Bool)) -> Int {
  case values {
    [] -> 0
    _ ->
      case list.length(values) < 11 {
        True -> 0
        False -> {
          let bits = take_bits(values, 11, 0)
          let rest = list.drop(values, 1)
          let points = case bits == 0x5D0 || bits == 0x05D {
            True -> 1
            False -> 0
          }
          points + finder_like_penalty(rest)
        }
      }
  }
}

fn take_bits(values: List(Bool), count: Int, acc: Int) -> Int {
  case values, count {
    _, 0 -> acc
    [value, ..rest], _ ->
      take_bits(rest, count - 1, acc * 2 + util.bool_to_int(value))
    [], _ -> acc
  }
}

fn penalty_n4(target: matrix.Matrix) -> Int {
  let dark = matrix.dark_count(target)
  let total = matrix.total_cells(target)
  let percentage = dark * 100 / total
  let deviation = percentage - 50
  let absolute = case deviation < 0 {
    True -> 0 - deviation
    False -> deviation
  }
  let lower_bucket = absolute / 5
  lower_bucket * 10
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

fn row_values(target: matrix.Matrix, row: Int) -> List(Bool) {
  int.range(from: matrix.width(target) - 1, to: -1, with: [], run: fn(acc, col) {
    [matrix.get(target, row, col), ..acc]
  })
}

fn column_values(target: matrix.Matrix, col: Int) -> List(Bool) {
  int.range(
    from: matrix.height(target) - 1,
    to: -1,
    with: [],
    run: fn(acc, row) { [matrix.get(target, row, col), ..acc] },
  )
}
