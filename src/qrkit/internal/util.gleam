//// Small helpers shared by qrkit internal modules.

import gleam/int
import gleam/list
import gleam/string

pub fn range(from start: Int, to stop: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..range(start + 1, stop)]
  }
}

pub fn at(list: List(a), index: Int) -> Result(a, Nil) {
  case list, index {
    _, i if i < 0 -> Error(Nil)
    [first, ..], 0 -> Ok(first)
    [_, ..rest], i -> at(rest, i - 1)
    [], _ -> Error(Nil)
  }
}

pub fn at_or(list: List(a), index: Int, default default: a) -> a {
  case at(list, index) {
    Ok(value) -> value
    Error(_) -> default
  }
}

pub fn replace_at(list: List(a), index: Int, with replacement: a) -> List(a) {
  case list, index {
    [], _ -> []
    [_, ..rest], 0 -> [replacement, ..rest]
    [first, ..rest], i -> [first, ..replace_at(rest, i - 1, with: replacement)]
  }
}

pub fn repeat(value: a, times count: Int) -> List(a) {
  list.repeat(value, count)
}

pub fn characters(text: String) -> List(String) {
  text
  |> string.to_utf_codepoints
  |> list.map(fn(codepoint) { string.from_utf_codepoints([codepoint]) })
}

/// Whether bit `index` (0 is the least significant) of `value` is set.
pub fn bit_at(value: Int, index: Int) -> Bool {
  int.bitwise_and(int.bitwise_shift_right(value, index), 1) == 1
}

pub fn bool_to_int(value: Bool) -> Int {
  case value {
    True -> 1
    False -> 0
  }
}

/// Surround `rows` with `margin` light modules on every side.
pub fn pad_rows(rows: List(List(Bool)), margin: Int) -> List(List(Bool)) {
  let width = case rows {
    [first, ..] -> list.length(first)
    [] -> 0
  }
  let padded_row = list.repeat(False, width + margin * 2)
  let body =
    rows
    |> list.map(fn(row) {
      list.append(
        list.repeat(False, margin),
        list.append(row, list.repeat(False, margin)),
      )
    })
  list.append(
    list.repeat(padded_row, margin),
    list.append(body, list.repeat(padded_row, margin)),
  )
}
