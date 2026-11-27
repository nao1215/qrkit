//// Mutation testing for qrkit. No mutation testing tool exists for Gleam, so
//// this one parses each module under src/ with glance, changes one operator
//// or boolean at a time, and runs `gleam test --target erlang` in a copy of
//// the project. Run it on the Erlang target:
////
////   gleam run -m mutation -- run [--workers N] [FILE ...]
////     Write every result to build/mutation/results.json.
////   gleam run -m mutation -- list [FILE ...]
////     Print the mutants without running them.
////   gleam run -m mutation -- gate
////     Fail on a survivor in build/mutation/results.json that
////     doc/mutation/baseline.json does not list. Survivors are matched by
////     module, function, mutator, line text and the column in that text, so
////     moved code still matches.
////   gleam run -m mutation -- baseline
////     Record build/mutation/results.json as the baseline and rewrite the
////     table in doc/testing.md.
////   gleam run -m mutation -- doc-check
////     Fail when the table in doc/testing.md does not match the baseline.
////
//// The property tests draw a new seed on each run, so a mutant they kill only
//// sometimes can live once. A survivor is run two more times and counts only
//// when it lives all three times.

import argv
import glance
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set
import gleam/string
import gleam/time/timestamp
import shellout
import simplifile

const results_path: String = "build/mutation/results.json"

const baseline_path: String = "doc/mutation/baseline.json"

const document_path: String = "doc/testing.md"

/// Generated data: mutating the table only tests the generator.
const excluded: List(String) = ["src/qrkit/internal/kanji_table.gleam"]

const retries: Int = 2

pub fn main() -> Nil {
  let code = case argv.load().arguments {
    ["run", "--workers", workers, ..files] ->
      case int.parse(workers) {
        Ok(workers) if workers > 0 -> run(workers, files)
        _ -> usage()
      }
    ["run", ..files] -> run(4, files)
    ["list", ..files] -> list_mutants(files)
    ["gate"] -> gate()
    ["baseline"] -> record_baseline()
    ["doc-check"] -> doc_check()
    _ -> usage()
  }
  case code {
    0 -> Nil
    _ -> halt(code)
  }
}

fn usage() -> Int {
  io.println(
    "usage: gleam run -m mutation -- run [--workers N] [FILE ...] | list [FILE ...] | gate | baseline | doc-check",
  )
  2
}

// Finding mutants ------------------------------------------------------------

type Mutant {
  Mutant(
    file: String,
    /// The unmutated module, read once so that edits made while a run is in
    /// progress do not leak into it.
    source: BitArray,
    offset: Int,
    length: Int,
    replacement: String,
    line: Int,
    text: String,
    column: Int,
    function: String,
    mutator: String,
  )
}

fn mutants(file: String) -> List(Mutant) {
  let assert Ok(source) = simplifile.read(file)
  let assert Ok(parsed) = glance.module(source)
  let bytes = bit_array.from_string(source)
  parsed.functions
  |> list.flat_map(fn(definition) {
    let function = definition.definition
    list.flat_map(function.body, statement_edits(_, bytes))
    |> list.map(fn(edit) {
      let #(offset, length, replacement) = edit
      let #(line, text, column) = line_at(bytes, offset)
      let assert Ok(original) = bit_array.slice(bytes, offset, length)
      let assert Ok(original) = bit_array.to_string(original)
      Mutant(
        file:,
        source: bytes,
        offset:,
        length:,
        replacement:,
        line:,
        text:,
        column:,
        function: function.name,
        mutator: case replacement {
          "" -> "drop " <> original
          _ -> original <> " -> " <> replacement
        },
      )
    })
  })
  |> list.sort(fn(a, b) { int.compare(a.offset, b.offset) })
}

/// An edit is the byte offset and length of the text to replace, and what
/// replaces it.
type Edit =
  #(Int, Int, String)

fn statement_edits(
  statement: glance.Statement,
  source: BitArray,
) -> List(Edit) {
  case statement {
    glance.Use(function:, ..) -> edits(function, source)
    glance.Assignment(value:, ..) -> edits(value, source)
    glance.Assert(expression:, ..) -> edits(expression, source)
    glance.Expression(expression) -> edits(expression, source)
  }
}

fn edits(expression: glance.Expression, source: BitArray) -> List(Edit) {
  let all = list.flat_map(_, edits(_, source))
  let fields = fn(fields) {
    list.flat_map(fields, fn(field) {
      case field {
        glance.LabelledField(item:, ..) | glance.UnlabelledField(item:) ->
          edits(item, source)
        glance.ShorthandField(..) -> []
      }
    })
  }
  let optional = fn(expression) {
    option.map(expression, edits(_, source)) |> option.unwrap([])
  }
  case expression {
    glance.Variable(location:, name: "True") -> [#(location.start, 4, "False")]
    glance.Variable(location:, name: "False") -> [#(location.start, 5, "True")]
    glance.NegateBool(location:, value:) -> [
      #(location.start, 1, ""),
      ..edits(value, source)
    ]
    glance.BinaryOperator(name:, left:, right:, ..) ->
      list.flatten([
        operator_edit(name, left, right, source),
        edits(left, source),
        edits(right, source),
      ])
    glance.NegateInt(value:, ..) -> edits(value, source)
    glance.Block(statements:, ..) ->
      list.flat_map(statements, statement_edits(_, source))
    glance.Fn(body:, ..) -> list.flat_map(body, statement_edits(_, source))
    glance.Tuple(elements:, ..) -> all(elements)
    glance.List(elements:, rest:, ..) ->
      list.append(all(elements), optional(rest))
    glance.RecordUpdate(record:, fields: updates, ..) ->
      list.append(
        edits(record, source),
        list.flat_map(updates, fn(update) { optional(update.item) }),
      )
    glance.FieldAccess(container:, ..) -> edits(container, source)
    glance.Call(function:, arguments:, ..) ->
      list.append(edits(function, source), fields(arguments))
    glance.TupleIndex(tuple:, ..) -> edits(tuple, source)
    glance.FnCapture(function:, arguments_before:, arguments_after:, ..) ->
      list.flatten([
        edits(function, source),
        fields(arguments_before),
        fields(arguments_after),
      ])
    glance.BitString(segments:, ..) ->
      list.flat_map(segments, fn(segment) { edits(segment.0, source) })
    glance.Case(subjects:, clauses:, ..) ->
      list.append(
        all(subjects),
        list.flat_map(clauses, fn(clause) {
          list.append(optional(clause.guard), edits(clause.body, source))
        }),
      )
    glance.Int(..)
    | glance.Float(..)
    | glance.String(..)
    | glance.Variable(..)
    | glance.Panic(..)
    | glance.Todo(..)
    | glance.Echo(..) -> []
  }
}

/// The replacements, in the style of gremlins and Stryker. Pipes and string
/// concatenation are left alone.
fn replacement(operator: glance.BinaryOperator) -> Option(#(String, String)) {
  case operator {
    glance.And -> Some(#("&&", "||"))
    glance.Or -> Some(#("||", "&&"))
    glance.Eq -> Some(#("==", "!="))
    glance.NotEq -> Some(#("!=", "=="))
    glance.LtInt -> Some(#("<", "<="))
    glance.LtEqInt -> Some(#("<=", "<"))
    glance.GtInt -> Some(#(">", ">="))
    glance.GtEqInt -> Some(#(">=", ">"))
    glance.LtFloat -> Some(#("<.", "<=."))
    glance.LtEqFloat -> Some(#("<=.", "<."))
    glance.GtFloat -> Some(#(">.", ">=."))
    glance.GtEqFloat -> Some(#(">=.", ">."))
    glance.AddInt -> Some(#("+", "-"))
    glance.SubInt -> Some(#("-", "+"))
    glance.MultInt -> Some(#("*", "/"))
    glance.DivInt -> Some(#("/", "*"))
    glance.RemainderInt -> Some(#("%", "*"))
    glance.AddFloat -> Some(#("+.", "-."))
    glance.SubFloat -> Some(#("-.", "+."))
    glance.MultFloat -> Some(#("*.", "/."))
    glance.DivFloat -> Some(#("/.", "*."))
    glance.Pipe | glance.Concatenate -> None
  }
}

/// glance records where the operands are, not the operator, so the operator
/// is the first occurrence of its text between them outside a comment.
fn operator_edit(
  operator: glance.BinaryOperator,
  left: glance.Expression,
  right: glance.Expression,
  source: BitArray,
) -> List(Edit) {
  case replacement(operator) {
    None -> []
    Some(#(text, with)) -> {
      let start = location(left).end
      let assert Ok(gap) =
        bit_array.slice(source, start, location(right).start - start)
      let assert Ok(gap) = bit_array.to_string(gap)
      case find_operator(gap, text, 0) {
        Ok(at) -> [#(start + at, string.byte_size(text), with)]
        Error(Nil) -> []
      }
    }
  }
}

fn find_operator(gap: String, text: String, at: Int) -> Result(Int, Nil) {
  case gap {
    "" -> Error(Nil)
    "//" <> _ ->
      case string.split_once(gap, "\n") {
        Ok(#(comment, rest)) ->
          find_operator(rest, text, at + string.byte_size(comment) + 1)
        Error(Nil) -> Error(Nil)
      }
    _ ->
      case string.starts_with(gap, text) {
        True -> Ok(at)
        False -> {
          let assert Ok(#(first, rest)) = string.pop_grapheme(gap)
          find_operator(rest, text, at + string.byte_size(first))
        }
      }
  }
}

fn location(expression: glance.Expression) -> glance.Span {
  case expression {
    glance.Int(location:, ..)
    | glance.Float(location:, ..)
    | glance.String(location:, ..)
    | glance.Variable(location:, ..)
    | glance.NegateInt(location:, ..)
    | glance.NegateBool(location:, ..)
    | glance.Block(location:, ..)
    | glance.Panic(location:, ..)
    | glance.Todo(location:, ..)
    | glance.Tuple(location:, ..)
    | glance.List(location:, ..)
    | glance.Fn(location:, ..)
    | glance.RecordUpdate(location:, ..)
    | glance.FieldAccess(location:, ..)
    | glance.Call(location:, ..)
    | glance.TupleIndex(location:, ..)
    | glance.FnCapture(location:, ..)
    | glance.BitString(location:, ..)
    | glance.Case(location:, ..)
    | glance.BinaryOperator(location:, ..)
    | glance.Echo(location:, ..) -> location
  }
}

/// The 1-based line number, the trimmed text of the line holding `offset`,
/// and the byte column of `offset` in that trimmed text. The column tells two
/// changes of the same operator on one line apart, and does not depend on the
/// indentation.
fn line_at(source: BitArray, offset: Int) -> #(Int, String, Int) {
  let assert Ok(before) = bit_array.slice(source, 0, offset)
  let assert Ok(before) = bit_array.to_string(before)
  let lines = string.split(before, "\n")
  let number = list.length(lines)
  let assert Ok(start) = list.last(lines)
  let assert Ok(source) = bit_array.to_string(source)
  let assert Ok(text) =
    string.split(source, "\n") |> list.drop(number - 1) |> list.first
  #(number, string.trim(text), string.byte_size(string.trim_start(start)))
}

fn apply(source: BitArray, mutant: Mutant) -> String {
  let size = bit_array.byte_size(source)
  let end = mutant.offset + mutant.length
  let assert Ok(head) = bit_array.slice(source, 0, mutant.offset)
  let assert Ok(tail) = bit_array.slice(source, end, size - end)
  let assert Ok(mutated) =
    bit_array.concat([head, bit_array.from_string(mutant.replacement), tail])
    |> bit_array.to_string
  mutated
}

// Running mutants ------------------------------------------------------------

type Status {
  Killed
  Lived
  TimedOut
  CompileError
}

type Row {
  Row(
    file: String,
    line: Int,
    column: Int,
    function: String,
    mutator: String,
    text: String,
    status: Status,
  )
}

fn source_files() -> List(String) {
  let assert Ok(files) = simplifile.get_files("src")
  files
  |> list.filter(fn(file) {
    string.ends_with(file, ".gleam") && !list.contains(excluded, file)
  })
  |> list.sort(string.compare)
}

fn chosen_files(files: List(String)) -> List(String) {
  case files {
    [] -> source_files()
    _ ->
      list.filter(files, fn(file) { !list.contains(excluded, file) })
      |> list.sort(string.compare)
  }
}

fn list_mutants(files: List(String)) -> Int {
  chosen_files(files)
  |> list.flat_map(mutants)
  |> list.each(fn(mutant) {
    io.println(
      mutant.file
      <> ":"
      <> int.to_string(mutant.line)
      <> " "
      <> mutant.function
      <> " "
      <> mutant.mutator
      <> " | "
      <> mutant.text,
    )
  })
  0
}

fn run(workers: Int, files: List(String)) -> Int {
  let files = chosen_files(files)
  let cases = list.flat_map(files, mutants)
  io.println(
    int.to_string(list.length(cases))
    <> " mutants in "
    <> int.to_string(list.length(files))
    <> " modules",
  )
  let root = "build/mutation/work"
  let _stale = simplifile.delete(root)
  let projects =
    int.range(from: 0, to: workers, with: [], run: fn(acc, i) { [i, ..acc] })
    |> list.reverse
    |> list.map(fn(index) {
      let project = root <> "/w" <> int.to_string(index)
      let assert Ok(Nil) = copy_project(project)
      project
    })
  let assert [first, ..] = projects
  let #(status, milliseconds) = test_in(first, 900)
  case status {
    Lived -> {
      let timeout = int.max(60, milliseconds * 4 / 1000)
      let indexed =
        list.index_map(cases, fn(mutant, index) { #(index, mutant) })
      let rows =
        parallel_map(list.index_map(projects, fn(p, i) { #(i, p) }), fn(worker) {
          let #(index, project) = worker
          indexed
          |> list.filter(fn(pair) { pair.0 % workers == index })
          |> list.map(fn(pair) { run_mutant(project, pair.1, timeout) })
        })
        |> list.flatten
        |> list.sort(fn(a, b) {
          string.compare(a.file, b.file)
          |> order_then(int.compare(a.line, b.line))
          |> order_then(int.compare(a.column, b.column))
          |> order_then(string.compare(a.mutator, b.mutator))
        })
      let _cleaned = simplifile.delete(root)
      write_results(files, rows)
      io.println(summary_line(rows))
      0
    }
    _ -> {
      io.println("the unmutated tests do not pass")
      2
    }
  }
}

fn order_then(first: order.Order, second: order.Order) -> order.Order {
  case first {
    order.Eq -> second
    _ -> first
  }
}

fn copy_project(destination: String) -> Result(Nil, simplifile.FileError) {
  use _ <- result.try(simplifile.create_directory_all(destination))
  [
    "gleam.toml", "manifest.toml", "src", "test", "dev", "build/packages",
    "build/dev",
  ]
  |> list.try_each(fn(entry) {
    let target = destination <> "/" <> entry
    case simplifile.is_directory(entry) {
      Ok(True) -> simplifile.copy_directory(entry, target)
      _ -> simplifile.copy_file(entry, target)
    }
  })
}

fn run_mutant(project: String, mutant: Mutant, timeout: Int) -> Row {
  let path = project <> "/" <> mutant.file
  let assert Ok(Nil) = simplifile.write(path, apply(mutant.source, mutant))
  let status = run_until_killed(project, timeout, retries)
  let assert Ok(Nil) = simplifile.write_bits(path, mutant.source)
  io.println(
    status_name(status)
    <> " "
    <> mutant.file
    <> ":"
    <> int.to_string(mutant.line)
    <> " "
    <> mutant.mutator,
  )
  Row(
    file: mutant.file,
    line: mutant.line,
    column: mutant.column,
    function: mutant.function,
    mutator: mutant.mutator,
    text: mutant.text,
    status:,
  )
}

fn run_until_killed(project: String, timeout: Int, retries: Int) -> Status {
  case test_in(project, timeout) {
    #(Lived, _) if retries > 0 -> run_until_killed(project, timeout, retries - 1)
    #(status, _) -> status
  }
}

fn test_in(project: String, timeout: Int) -> #(Status, Int) {
  let started = monotonic_milliseconds()
  let outcome =
    shellout.command(
      run: "timeout",
      with: [int.to_string(timeout), "gleam", "test", "--target", "erlang"],
      in: project,
      opt: [],
    )
  let elapsed = monotonic_milliseconds() - started
  let status = case outcome {
    Ok(_) -> Lived
    Error(#(124, _)) -> TimedOut
    Error(#(_, output)) ->
      case
        string.contains(output, "error: ")
        && !string.contains(output, " passed")
      {
        True -> CompileError
        False -> Killed
      }
  }
  #(status, elapsed)
}

// Results --------------------------------------------------------------------

fn status_name(status: Status) -> String {
  case status {
    Killed -> "KILLED"
    Lived -> "LIVED"
    TimedOut -> "TIMED_OUT"
    CompileError -> "COMPILE_ERROR"
  }
}

fn row_to_json(row: Row) -> json.Json {
  json.object([
    #("file", json.string(row.file)),
    #("line", json.int(row.line)),
    #("column", json.int(row.column)),
    #("function", json.string(row.function)),
    #("mutator", json.string(row.mutator)),
    #("text", json.string(row.text)),
    #("status", json.string(status_name(row.status))),
  ])
}

fn row_decoder() -> decode.Decoder(Row) {
  use file <- decode.field("file", decode.string)
  use line <- decode.field("line", decode.int)
  use column <- decode.field("column", decode.int)
  use function <- decode.field("function", decode.string)
  use mutator <- decode.field("mutator", decode.string)
  use text <- decode.field("text", decode.string)
  use status <- decode.field("status", decode.string)
  let status = case status {
    "KILLED" -> Killed
    "LIVED" -> Lived
    "TIMED_OUT" -> TimedOut
    _ -> CompileError
  }
  decode.success(Row(file:, line:, column:, function:, mutator:, text:, status:))
}

type Results {
  Results(files: List(String), rows: List(Row))
}

fn read_results(path: String) -> Results {
  let assert Ok(text) = simplifile.read(path)
  let decoder = {
    use files <- decode.field("files", decode.list(decode.string))
    use rows <- decode.field("mutants", decode.list(row_decoder()))
    decode.success(Results(files:, rows:))
  }
  let assert Ok(results) = json.parse(text, decoder)
  results
}

type Summary {
  Summary(killed: Int, lived: Int, timed_out: Int, compile_error: Int)
}

fn summarise(rows: List(Row)) -> Summary {
  let count = fn(status) { list.count(rows, fn(row) { row.status == status }) }
  Summary(
    killed: count(Killed),
    lived: count(Lived),
    timed_out: count(TimedOut),
    compile_error: count(CompileError),
  )
}

/// Killed / (killed + lived + timed out) in tenths of a percent. A timed-out
/// mutant counts as killed: the change made a test hang.
fn score(summary: Summary) -> String {
  let detected = summary.killed + summary.timed_out
  case detected + summary.lived {
    0 -> "100.0%"
    executed -> {
      let tenths = { detected * 1000 + executed / 2 } / executed
      int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10) <> "%"
    }
  }
}

fn summary_line(rows: List(Row)) -> String {
  let summary = summarise(rows)
  "score "
  <> score(summary)
  <> ": "
  <> int.to_string(summary.killed)
  <> " killed, "
  <> int.to_string(summary.lived)
  <> " lived, "
  <> int.to_string(summary.timed_out)
  <> " timed out, "
  <> int.to_string(summary.compile_error)
  <> " did not compile"
}

fn write_results(files: List(String), rows: List(Row)) -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all("build/mutation")
  let assert Ok(Nil) = simplifile.write(results_path, results_json(files, rows))
  Nil
}

/// One mutant per line keeps the baseline diff readable. Each row is
/// serialised on its own, so a line of source holding `},{` stays intact.
fn results_json(files: List(String), rows: List(Row)) -> String {
  "{\"files\":"
  <> json.to_string(json.array(files, json.string))
  <> ",\"mutants\":[\n"
  <> string.join(
    list.map(rows, fn(row) { json.to_string(row_to_json(row)) }),
    ",\n",
  )
  <> "\n]}\n"
}

fn key(row: Row) -> #(String, String, String, String, Int) {
  #(row.file, row.function, row.mutator, row.text, row.column)
}

fn gate() -> Int {
  let known =
    read_results(baseline_path).rows
    |> list.filter(fn(row) { row.status == Lived })
    |> list.map(key)
    |> set.from_list
  let results = read_results(results_path)
  let new =
    list.filter(results.rows, fn(row) {
      row.status == Lived && !set.contains(known, key(row))
    })
  list.each(new, fn(row) {
    io.println(
      "new survivor "
      <> row.file
      <> ":"
      <> int.to_string(row.line)
      <> " in "
      <> row.function
      <> ": "
      <> row.mutator
      <> "\n    "
      <> row.text,
    )
  })
  case new {
    [] -> {
      io.println(
        "no new survivors among "
        <> int.to_string(list.length(results.rows))
        <> " mutants",
      )
      0
    }
    _ -> {
      io.println(
        int.to_string(list.length(new))
        <> " mutants live that the baseline does not list. Add a test that kills them, or record them with `gleam run -m mutation -- baseline` and say why in doc/testing.md.",
      )
      1
    }
  }
}

fn record_baseline() -> Int {
  let results = read_results(results_path)
  case results.files == source_files() {
    False -> {
      io.println("the baseline needs a run over every module")
      2
    }
    True -> {
      let assert Ok(Nil) = simplifile.create_directory_all("doc/mutation")
      let assert Ok(Nil) =
        simplifile.write(
          baseline_path,
          results_json(results.files, results.rows),
        )
      let assert Ok(Nil) =
        simplifile.write(document_path, render_document(results.rows))
      0
    }
  }
}

fn doc_check() -> Int {
  let assert Ok(current) = simplifile.read(document_path)
  case current == render_document(read_results(baseline_path).rows) {
    True -> 0
    False -> {
      io.println(
        "doc/testing.md does not match doc/mutation/baseline.json; run `gleam run -m mutation -- baseline`",
      )
      1
    }
  }
}

fn table(rows: List(Row)) -> String {
  let modules =
    list.map(rows, fn(row) { row.file })
    |> list.unique
    |> list.sort(string.compare)
  let line = fn(name, rows) {
    let s = summarise(rows)
    "| "
    <> name
    <> " | "
    <> int.to_string(s.killed)
    <> " | "
    <> int.to_string(s.lived)
    <> " | "
    <> int.to_string(s.timed_out)
    <> " | "
    <> score(s)
    <> " |"
  }
  [
    "| Module | Killed | Lived | Timed out | Score |",
    "|---|---:|---:|---:|---:|",
    ..list.map(modules, fn(module) {
      let name =
        module
        |> string.replace("src/", "")
        |> string.replace(".gleam", "")
      line(
        "`" <> name <> "`",
        list.filter(rows, fn(row) { row.file == module }),
      )
    })
  ]
  |> list.append([line("all", rows)])
  |> string.join("\n")
}

fn render_document(rows: List(Row)) -> String {
  let assert Ok(text) = simplifile.read(document_path)
  let assert Ok(#(head, rest)) =
    string.split_once(text, "<!-- mutation:start -->")
  let assert Ok(#(_, tail)) = string.split_once(rest, "<!-- mutation:end -->")
  head
  <> "<!-- mutation:start -->\n"
  <> table(rows)
  <> "\n<!-- mutation:end -->"
  <> tail
}

/// Runs `fun` on every item in its own Erlang process. Other targets run the
/// items one by one.
@external(erlang, "mutation_ffi", "parallel_map")
fn parallel_map(items: List(a), fun: fn(a) -> b) -> List(b) {
  list.map(items, fun)
}

/// Milliseconds from Erlang's monotonic clock, which never goes back. Other
/// targets fall back to the wall clock.
@external(erlang, "mutation_ffi", "monotonic_milliseconds")
fn monotonic_milliseconds() -> Int {
  let #(seconds, nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  seconds * 1000 + nanoseconds / 1_000_000
}

@external(erlang, "erlang", "halt")
@external(javascript, "node:process", "exit")
fn halt(code: Int) -> Nil
