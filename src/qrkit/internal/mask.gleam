//// Standard QR data masks and penalty scoring.

import gleam/list
import qrkit/internal/matrix
import qrkit/internal/util

pub fn apply(mask: Int, to target: matrix.Matrix) -> matrix.Matrix {
  do_apply(mask, target, 0, 0)
}

fn do_apply(
  mask: Int,
  target: matrix.Matrix,
  row: Int,
  col: Int,
) -> matrix.Matrix {
  case row >= matrix.height(target) {
    True -> target
    False ->
      case col >= matrix.width(target) {
        True -> do_apply(mask, target, row + 1, 0)
        False ->
          case matrix.is_reserved(target, row, col) {
            True -> do_apply(mask, target, row, col + 1)
            False ->
              do_apply(
                mask,
                matrix.xor(target, row, col, mask_at(mask, row, col)),
                row,
                col + 1,
              )
          }
      }
  }
}

pub fn best_mask(target: matrix.Matrix) -> Int {
  do_best_mask(target, 0, 0, 0)
}

fn do_best_mask(
  target: matrix.Matrix,
  mask: Int,
  best_mask: Int,
  best_penalty: Int,
) -> Int {
  case mask > 7 {
    True -> best_mask
    False -> {
      let penalty = penalty_total(apply(mask, to: target))
      case mask == 0 || penalty < best_penalty {
        True -> do_best_mask(target, mask + 1, mask, penalty)
        False -> do_best_mask(target, mask + 1, best_mask, best_penalty)
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

pub fn penalty_n1(target: matrix.Matrix) -> Int {
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

pub fn penalty_n2(target: matrix.Matrix) -> Int {
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
            bool_to_int(matrix.get(target, row, col))
            + bool_to_int(matrix.get(target, row, col + 1))
            + bool_to_int(matrix.get(target, row + 1, col))
            + bool_to_int(matrix.get(target, row + 1, col + 1))
          let next_acc = case dark_total == 0 || dark_total == 4 {
            True -> acc + 1
            False -> acc
          }
          do_penalty_n2(target, row, col + 1, next_acc)
        }
      }
  }
}

pub fn penalty_n3(target: matrix.Matrix) -> Int {
  let rows =
    util.range(0, matrix.height(target) - 1)
    |> list.fold(0, fn(acc, row) {
      acc + finder_like_penalty(row_values(target, row))
    })
  let columns =
    util.range(0, matrix.width(target) - 1)
    |> list.fold(0, fn(acc, col) {
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
      take_bits(rest, count - 1, acc * 2 + bool_to_int(value))
    [], _ -> acc
  }
}

pub fn penalty_n4(target: matrix.Matrix) -> Int {
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
  util.range(0, matrix.width(target) - 1)
  |> list.map(fn(col) { matrix.get(target, row, col) })
}

fn column_values(target: matrix.Matrix, col: Int) -> List(Bool) {
  util.range(0, matrix.height(target) - 1)
  |> list.map(fn(row) { matrix.get(target, row, col) })
}

fn bool_to_int(value: Bool) -> Int {
  case value {
    True -> 1
    False -> 0
  }
}
