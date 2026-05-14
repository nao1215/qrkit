//// Small helpers shared by qrkit internal modules.

import gleam/list
import gleam/string

pub fn range(from start: Int, to stop: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..range(start + 1, stop)]
  }
}

pub fn reverse_range(from start: Int, down_to stop: Int) -> List(Int) {
  case start < stop {
    True -> []
    False -> [start, ..reverse_range(start - 1, stop)]
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

pub fn join(strings: List(String), separator: String) -> String {
  string.join(strings, with: separator)
}
