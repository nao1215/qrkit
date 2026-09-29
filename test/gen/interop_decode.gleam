//// Decode symbols written by another encoder: `gleam run -m
//// gen/interop_decode` reads build/interop/segno.tsv (written by
//// `scripts/interop.py segno`), one symbol per line as `label \t text (UTF-8
//// hex) \t rows`, where the text is what zxing-cpp reads from the symbol. It
//// fails when qrkit/decode reads anything else, or when a line labelled
//// `sequence-<i>/<n>` has no Structured Append header.

import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import qrkit/decode
import qrkit/error
import simplifile

const path: String = "build/interop/segno.tsv"

pub fn main() -> Nil {
  let assert Ok(content) = simplifile.read(path)
  let lines = string.split(content, "\n") |> list.filter(fn(l) { l != "" })
  let failures = list.filter_map(lines, check)
  list.each(failures, io.println)
  io.println(
    "qrkit/decode agreed with zxing-cpp on "
    <> int.to_string(list.length(lines) - list.length(failures))
    <> " of "
    <> int.to_string(list.length(lines))
    <> " segno symbols",
  )
  // Fail the job when any symbol disagreed.
  let assert [] = failures
  Nil
}

fn check(line: String) -> Result(String, Nil) {
  let assert [label, hex, rows_text] = string.split(line, "\t")
  let assert Ok(bytes) = bit_array.base16_decode(string.uppercase(hex))
  let assert Ok(expected) = bit_array.to_string(bytes)
  let rows =
    string.split(rows_text, "/")
    |> list.map(fn(row) {
      string.to_graphemes(row) |> list.map(fn(c) { c == "1" })
    })
  let describe = fn(got) { label <> " " <> quoted(expected) <> " -> " <> got }
  case decode.from_rows(rows) {
    Error(e) -> Ok("ERROR " <> describe(describe_error(e)))
    Ok(decoded) -> {
      let header_ok =
        !string.starts_with(label, "sequence-")
        || option.is_some(decode.structured_append(decoded))
      case decode.text(decoded) == expected && header_ok {
        True -> Error(Nil)
        False -> Ok("MISMATCH " <> describe(quoted(decode.text(decoded))))
      }
    }
  }
}

fn quoted(text: String) -> String {
  "\"" <> string.replace(text, "\n", "\\n") <> "\""
}

fn describe_error(e: error.DecodeError) -> String {
  case e {
    error.NotASymbol(width, height) ->
      "NotASymbol("
      <> int.to_string(width)
      <> "x"
      <> int.to_string(height)
      <> ")"
    error.UnreadableFormatInformation -> "UnreadableFormatInformation"
    error.TooManyErrors -> "TooManyErrors"
    error.MalformedData(reason) -> "MalformedData(" <> reason <> ")"
  }
}
