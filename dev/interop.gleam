//// Differential testing against zxing-cpp, zbar and segno (doc/interop.md).
//// `just interop` writes the corpora and calls scripts/interop.py for the
//// Python readers; this module counts the results.
////
////   gleam run -m interop -- check
////     Count, per group, the symbols each reader read back as written, decode
////     build/interop/segno.tsv with qrkit, and write
////     build/interop/results.json. Fails when a gated group disagrees.
////   gleam run -m interop -- record
////     Copy the results to doc/interop/results.json with today's date and
////     rewrite the table in doc/interop.md and docs/images/interop.svg.
////   gleam run -m interop -- doc-check
////     Fail when the table or chart does not match doc/interop/results.json.

import argv
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import qrkit
import simplifile

const results_path: String = "build/interop/results.json"

const recorded_path: String = "doc/interop/results.json"

const document_path: String = "doc/interop.md"

const chart_path: String = "docs/images/interop.svg"

/// The order the table and chart list the groups in.
const order: List(String) = [
  "Standard QR", "Standard QR, ASCII", "Standard QR, ECI 26",
  "Standard QR, non-ASCII, no ECI", "Micro QR", "rMQR", "Structured Append",
]

/// Byte data without an ECI has no agreed character set, and zbar guesses
/// Shift JIS. This group is recorded but never fails a run.
const recorded_only: String = "Standard QR, non-ASCII, no ECI"

pub fn main() -> Nil {
  let code = case argv.load().arguments {
    ["check"] -> check()
    ["record"] -> record()
    ["doc-check"] -> doc_check()
    _ -> {
      io.println("usage: gleam run -m interop -- check | record | doc-check")
      2
    }
  }
  case code {
    0 -> Nil
    _ -> halt(code)
  }
}

type Group {
  Group(name: String, read: Int, total: Int)
}

type Check {
  Check(writer: String, reader: String, groups: List(Group))
}

type Results {
  Results(date: String, versions: List(String), checks: List(Check))
}

// Counting -------------------------------------------------------------------

/// One symbol: the group it is counted in, whether the reader agreed, and
/// what to print when it did not.
type Outcome {
  Outcome(group: String, agreed: Bool, report: String)
}

fn check() -> Int {
  let #(zxing_version, zxing) = read_lines("build/interop/zxing.tsv")
  let #(zbar_version, zbar) = read_lines("build/interop/zbar.tsv")
  let #(segno_version, segno) = read_lines("build/interop/segno.tsv")
  let checks = [
    tally("qrkit", "zxing-cpp", list.map(zxing, read_back(_, False))),
    tally("qrkit", "zbar", list.map(zbar, read_back(_, True))),
    tally("segno", "qrkit", list.map(segno, decode_segno)),
  ]
  let results =
    Results(
      date: "",
      versions: [zxing_version, zbar_version, segno_version],
      checks: list.map(checks, fn(pair) { pair.0 }),
    )
  let assert Ok(Nil) =
    simplifile.write(results_path, json.to_string(results_json(results)))
  let failures = list.flat_map(checks, fn(pair) { pair.1 })
  list.each(failures, io.println)
  list.each(results.checks, fn(check) {
    list.each(check.groups, fn(group) {
      io.println(
        check.reader
        <> " read "
        <> int.to_string(group.read)
        <> " of "
        <> int.to_string(group.total)
        <> " "
        <> check.writer
        <> " symbols: "
        <> group.name,
      )
    })
  })
  case failures {
    [] -> 0
    _ -> 1
  }
}

/// Splits a file written by scripts/interop.py into its version line and
/// its symbol lines.
fn read_lines(path: String) -> #(String, List(List(String))) {
  let assert Ok(content) = simplifile.read(path)
  let lines = string.split(content, "\n") |> list.filter(fn(l) { l != "" })
  let assert [header, ..rest] = lines
  #(string.drop_start(header, 2), list.map(rest, string.split(_, "\t")))
}

fn tally(
  writer: String,
  reader: String,
  outcomes: List(Outcome),
) -> #(Check, List(String)) {
  let groups =
    order
    |> list.filter_map(fn(name) {
      case list.filter(outcomes, fn(o) { o.group == name }) {
        [] -> Error(Nil)
        members ->
          Ok(Group(
            name:,
            read: list.count(members, fn(o) { o.agreed }),
            total: list.length(members),
          ))
      }
    })
  let failures =
    list.filter_map(outcomes, fn(o) {
      case o.agreed || o.group == recorded_only {
        True -> Error(Nil)
        False -> Ok("MISMATCH " <> reader <> " " <> o.group <> ": " <> o.report)
      }
    })
  #(Check(writer:, reader:, groups:), failures)
}

/// A qrkit symbol read by zxing-cpp or zbar:
/// `symbol level eci text rows got`, texts in UTF-8 hex.
fn read_back(fields: List(String), zbar: Bool) -> Outcome {
  let assert [symbol, level, eci, text, rows, got] = fields
  let text = from_hex(text)
  let family = case symbol {
    "qr" -> "Standard QR"
    "micro" -> "Micro QR"
    _ -> "rMQR"
  }
  let group = case zbar, eci, string.to_utf_codepoints(text) {
    False, "26", _ -> family <> ", ECI 26"
    False, _, _ -> family
    True, "26", _ -> "Standard QR, ECI 26"
    True, _, codepoints ->
      case
        list.all(codepoints, fn(c) { string.utf_codepoint_to_int(c) < 128 })
      {
        True -> "Standard QR, ASCII"
        False -> recorded_only
      }
  }
  let got = case got {
    "-" -> option.None
    hex -> option.Some(from_hex(hex))
  }
  Outcome(
    group:,
    agreed: got == option.Some(text),
    report: symbol
      <> "-"
      <> level
      <> " "
      <> quoted(text)
      <> " -> "
      <> case got {
      option.Some(got) -> quoted(got)
      option.None -> "nothing"
    }
      <> " rows="
      <> rows,
  )
}

/// A segno symbol read by qrkit: `label text rows`, where the text is what
/// zxing-cpp read and a `sequence-<i>/<n>` symbol must carry a Structured
/// Append header.
fn decode_segno(fields: List(String)) -> Outcome {
  let assert [label, text, rows_text] = fields
  let expected = from_hex(text)
  let rows =
    string.split(rows_text, "/")
    |> list.map(fn(row) {
      string.to_graphemes(row) |> list.map(fn(c) { c == "1" })
    })
  let result = qrkit.decode(rows)
  // segno writes an ECI header only when the text is not ISO-8859-1, so the
  // `qr-eci` label does not say whether a symbol has one. The header qrkit
  // read decides the group; the text still has to match zxing-cpp's.
  let group = case label, result {
    "micro", _ -> "Micro QR"
    "qr", Ok(qrkit.Decoded(eci: option.Some(_), ..))
    | "qr-eci", Ok(qrkit.Decoded(eci: option.Some(_), ..))
    -> "Standard QR, ECI 26"
    "qr", _ | "qr-eci", _ -> "Standard QR"
    _, _ -> "Structured Append"
  }
  let agreed = case result {
    Ok(decoded) ->
      decoded.text == expected
      && {
        !string.starts_with(label, "sequence-")
        || option.is_some(decoded.structured_append)
      }
    Error(_) -> False
  }
  Outcome(
    group:,
    agreed:,
    report: label
      <> " "
      <> quoted(expected)
      <> " -> "
      <> case result {
      Ok(decoded) -> quoted(decoded.text)
      Error(qrkit.NotASymbol(..)) -> "NotASymbol"
      Error(qrkit.UnreadableFormatInformation) -> "UnreadableFormatInformation"
      Error(qrkit.TooManyErrors) -> "TooManyErrors"
      Error(qrkit.MalformedData) -> "MalformedData"
    }
      <> " rows="
      <> rows_text,
  )
}

fn quoted(text: String) -> String {
  "\"" <> string.replace(text, "\n", "\\n") <> "\""
}

fn from_hex(hex: String) -> String {
  let assert Ok(bytes) = bit_array.base16_decode(string.uppercase(hex))
  let assert Ok(text) = bit_array.to_string(bytes)
  text
}

// Recording ------------------------------------------------------------------

fn record() -> Int {
  let assert Ok(text) = simplifile.read(results_path)
  let assert Ok(results) = json.parse(text, results_decoder())
  let #(date, _) =
    timestamp.system_time() |> timestamp.to_calendar(calendar.utc_offset)
  let results =
    Results(
      ..results,
      date: int.to_string(date.year)
        <> "-"
        <> pad(calendar.month_to_int(date.month))
        <> "-"
        <> pad(date.day),
    )
  let assert Ok(Nil) = simplifile.create_directory_all("doc/interop")
  let assert Ok(Nil) =
    simplifile.write(
      recorded_path,
      json.to_string(results_json(results))
      |> string.replace("},{", "},\n{")
        <> "\n",
    )
  let assert Ok(Nil) = simplifile.write(chart_path, chart(results))
  let assert Ok(Nil) = simplifile.write(document_path, render_document(results))
  0
}

fn doc_check() -> Int {
  let assert Ok(text) = simplifile.read(recorded_path)
  let assert Ok(results) = json.parse(text, results_decoder())
  let assert Ok(document) = simplifile.read(document_path)
  let assert Ok(figure) = simplifile.read(chart_path)
  case document == render_document(results), figure == chart(results) {
    True, True -> 0
    _, _ -> {
      io.println(
        "doc/interop.md or docs/images/interop.svg does not match doc/interop/results.json; run `gleam run -m interop -- record`",
      )
      1
    }
  }
}

fn pad(value: Int) -> String {
  string.pad_start(int.to_string(value), to: 2, with: "0")
}

fn results_json(results: Results) -> json.Json {
  json.object([
    #("date", json.string(results.date)),
    #("versions", json.array(results.versions, json.string)),
    #(
      "checks",
      json.array(results.checks, fn(check) {
        json.object([
          #("writer", json.string(check.writer)),
          #("reader", json.string(check.reader)),
          #(
            "groups",
            json.array(check.groups, fn(group) {
              json.object([
                #("name", json.string(group.name)),
                #("read", json.int(group.read)),
                #("total", json.int(group.total)),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
}

fn results_decoder() -> decode.Decoder(Results) {
  let group = {
    use name <- decode.field("name", decode.string)
    use read <- decode.field("read", decode.int)
    use total <- decode.field("total", decode.int)
    decode.success(Group(name:, read:, total:))
  }
  let check = {
    use writer <- decode.field("writer", decode.string)
    use reader <- decode.field("reader", decode.string)
    use groups <- decode.field("groups", decode.list(group))
    decode.success(Check(writer:, reader:, groups:))
  }
  use date <- decode.field("date", decode.string)
  use versions <- decode.field("versions", decode.list(decode.string))
  use checks <- decode.field("checks", decode.list(check))
  decode.success(Results(date:, versions:, checks:))
}

/// The share read, in tenths of a percent.
fn tenths(group: Group) -> Int {
  case group.total {
    0 -> 1000
    total -> { group.read * 1000 + total / 2 } / total
  }
}

fn percent(group: Group) -> String {
  let t = tenths(group)
  int.to_string(t / 10) <> "." <> int.to_string(t % 10) <> "%"
}

fn render_document(results: Results) -> String {
  let rows =
    list.flat_map(results.checks, fn(check) {
      list.map(check.groups, fn(group) {
        "| "
        <> check.writer
        <> " | "
        <> check.reader
        <> " | "
        <> group.name
        <> " | "
        <> int.to_string(group.read)
        <> " / "
        <> int.to_string(group.total)
        <> " | "
        <> percent(group)
        <> " | "
        <> case group.name == recorded_only {
          True -> "recorded only"
          False -> "must be 100%"
        }
        <> " |"
      })
    })
  let table =
    [
      "Measured on "
        <> results.date
        <> " with "
        <> string.join(results.versions, ", ")
        <> ".",
      "",
      "| Writer | Reader | Symbols | Read | Rate | Gate |",
      "|---|---|---|---:|---:|---|",
      ..rows
    ]
    |> string.join("\n")
  let assert Ok(text) = simplifile.read(document_path)
  let assert Ok(#(head, rest)) =
    string.split_once(text, "<!-- interop:start -->")
  let assert Ok(#(_, tail)) = string.split_once(rest, "<!-- interop:end -->")
  head
  <> "<!-- interop:start -->\n"
  <> table
  <> "\n<!-- interop:end -->"
  <> tail
}

/// A horizontal bar per group: the share of symbols the reader agreed on.
fn chart(results: Results) -> String {
  let rows =
    list.flat_map(results.checks, fn(check) {
      list.map(check.groups, fn(group) {
        #(check.writer <> " → " <> check.reader <> ": " <> group.name, group)
      })
    })
  let label_width = 360
  let bar_width = 300
  let row_height = 26
  let top = 34
  let height = top + row_height * list.length(rows) + 12
  let width = label_width + bar_width + 70
  let bars =
    list.index_map(rows, fn(row, index) {
      let #(label, group) = row
      let y = top + index * row_height
      let class = case group.name == recorded_only {
        True -> "info"
        False -> "pass"
      }
      let filled = bar_width * tenths(group) / 1000
      "<text x=\"0\" y=\""
      <> int.to_string(y + 15)
      <> "\">"
      <> label
      <> "</text>\n<rect class=\"track\" x=\""
      <> int.to_string(label_width)
      <> "\" y=\""
      <> int.to_string(y + 3)
      <> "\" width=\""
      <> int.to_string(bar_width)
      <> "\" height=\"16\" rx=\"3\"/>\n<rect class=\""
      <> class
      <> "\" x=\""
      <> int.to_string(label_width)
      <> "\" y=\""
      <> int.to_string(y + 3)
      <> "\" width=\""
      <> int.to_string(filled)
      <> "\" height=\"16\" rx=\"3\"/>\n<text x=\""
      <> int.to_string(label_width + bar_width + 8)
      <> "\" y=\""
      <> int.to_string(y + 15)
      <> "\">"
      <> percent(group)
      <> "</text>"
    })
  [
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\""
      <> int.to_string(width)
      <> "\" height=\""
      <> int.to_string(height)
      <> "\" viewBox=\"0 0 "
      <> int.to_string(width)
      <> " "
      <> int.to_string(height)
      <> "\" font-family=\"-apple-system,Segoe UI,Helvetica,Arial,sans-serif\" font-size=\"13\">",
    "<style>text{fill:#1f2328}.track{fill:#eaeef2}.pass{fill:#1a7f37}.info{fill:#9a6700}@media (prefers-color-scheme:dark){text{fill:#e6edf3}.track{fill:#30363d}.pass{fill:#3fb950}.info{fill:#d29922}}</style>",
    "<text x=\"0\" y=\"18\" font-weight=\"600\">Symbols read back as written (green: must be 100%, amber: recorded only)</text>",
    ..bars
  ]
  |> list.append(["</svg>"])
  |> string.join("\n")
  <> "\n"
}

@external(erlang, "erlang", "halt")
@external(javascript, "node:process", "exit")
fn halt(code: Int) -> Nil
