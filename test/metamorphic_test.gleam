//// Metamorphic tests: relations between two runs whose exact output the
//// test cannot state on its own.
////
//// - The encoder picks the smallest symbol that holds the payload, so a
////   longer payload or a stronger error correction level never yields a
////   smaller symbol.
//// - The decoder reads the same text after the grid is rotated, mirrored or
////   surrounded by a light quiet zone.
////
//// The nightly workflow runs these with METAMON_RUNS_MULTIPLIER as well.

import generators
import gleam/list
import gleam/result
import gleam/string
import metamon
import metamon/generator
import qrkit

type Request =
  #(String, qrkit.Symbol, qrkit.ErrorCorrection)

fn request() -> generator.Generator(Request) {
  generator.tuple3(generators.text(), generators.symbol(), generators.ecc())
}

fn build(input: Request) -> Result(qrkit.QrCode, qrkit.EncodeError) {
  let #(text, symbol, ecc) = input
  qrkit.encode_with(
    text,
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: symbol,
      error_correction: ecc,
    ),
  )
}

/// The number of modules of the chosen symbol, or `Error` when the request
/// does not fit any size. An error ranks above every size.
fn modules(input: Request) -> Result(Int, Nil) {
  build(input)
  |> result.map(fn(qr) { qr.width * qr.height })
  |> result.replace_error(Nil)
}

fn not_larger(left: Result(Int, Nil), right: Result(Int, Nil)) -> Bool {
  case left, right {
    Ok(a), Ok(b) -> a <= b
    Ok(_), Error(_) -> True
    Error(_), Error(_) -> True
    Error(_), Ok(_) -> False
  }
}

fn append(suffix: String) -> metamon.Transform(Request) {
  metamon.Transform(name: "append " <> suffix, apply: fn(input: Request) {
    let #(text, symbol, ecc) = input
    #(text <> suffix, symbol, ecc)
  })
}

fn not_smaller() -> metamon.Relation(Result(Int, Nil)) {
  metamon.Relation(name: "not smaller", holds: not_larger)
}

/// `transform` applied `times` times.
fn repeat(
  transform: metamon.Transform(a),
  name: String,
  times: Int,
) -> metamon.Transform(a) {
  metamon.Transform(name:, apply: fn(value) {
    list.fold(list.repeat(transform.apply, times), value, fn(acc, apply) {
      apply(acc)
    })
  })
}

pub fn longer_payload_never_gets_a_smaller_symbol_test() -> Nil {
  metamon.forall_morph(
    request(),
    list.map(["7", "Z", "z", "漢", "é"], fn(suffix) {
      metamon.Morph(
        name: "append " <> suffix,
        transform: append(suffix),
        relation: not_smaller(),
      )
    }),
    modules,
  )
}

/// The next stronger level the symbol family supports, or the same level
/// when it is already the strongest. rMQR has only Medium and High, Micro QR
/// stops at Quartile, and Low stays Low for rMQR because it is rejected there.
fn stronger(input: Request) -> Request {
  let #(text, symbol, ecc) = input
  let next = case symbol, ecc {
    qrkit.Rectangular, qrkit.Medium -> qrkit.High
    qrkit.Rectangular, other -> other
    qrkit.Micro, qrkit.Low -> qrkit.Medium
    qrkit.Micro, qrkit.Medium -> qrkit.Quartile
    qrkit.Micro, other -> other
    qrkit.Standard, qrkit.Low -> qrkit.Medium
    qrkit.Standard, qrkit.Medium -> qrkit.Quartile
    qrkit.Standard, _ -> qrkit.High
  }
  #(text, symbol, next)
}

/// Payloads long enough to cross the version 9/10 and 26/27 boundaries of
/// Standard QR, where the character-count fields get wider.
fn long_request() -> generator.Generator(Request) {
  let char =
    generator.frequency([
      #(3, generator.character(of: generator.Digits)),
      #(
        2,
        generator.string_from(
          characters: generator.element_of(upper_letters()),
          length: generator.range(from: 1, to: 1),
        ),
      ),
      #(1, generator.character(of: generator.PrintableAscii)),
    ])
  generator.tuple3(
    generator.string_from(
      characters: char,
      length: generator.range(from: 150, to: 500),
    ),
    generator.return(qrkit.Standard),
    generators.ecc(),
  )
}

fn upper_letters() -> List(String) {
  string.split("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "")
}

/// Each run builds two symbols of version 10 to 30, so this test keeps its
/// own small run count: the nightly job multiplies it by 10 and eunit stops a
/// test after 5 seconds.
pub fn longer_long_payload_never_gets_a_smaller_symbol_test() -> Nil {
  metamon.forall_morph_with(
    metamon.Config(..metamon.default_config(), runs: 10),
    long_request(),
    [
      metamon.Morph(
        name: "append 7",
        transform: append("7"),
        relation: not_smaller(),
      ),
    ],
    modules,
  )
}

pub fn stronger_error_correction_never_gets_a_smaller_symbol_test() -> Nil {
  metamon.forall_morph(
    request(),
    [
      metamon.Morph(
        name: "raise error correction one level",
        transform: metamon.Transform(name: "stronger", apply: stronger),
        relation: not_smaller(),
      ),
    ],
    modules,
  )
}

/// Rows of a symbol, or no rows when the request does not fit. The decoder
/// rejects an empty grid, and does so after every transform as well.
fn rows_of(
  g: generator.Generator(Request),
) -> generator.Generator(List(List(Bool))) {
  g
  |> generator.map(fn(input) {
    build(input)
    |> result.map(fn(qr) { qr.rows })
    |> result.unwrap([])
  })
}

fn transpose(rows: List(List(Bool))) -> List(List(Bool)) {
  case rows {
    [] -> []
    _ -> list.transpose(rows)
  }
}

fn rotate_clockwise(rows: List(List(Bool))) -> List(List(Bool)) {
  rows |> list.reverse |> transpose
}

fn pad(rows: List(List(Bool)), by: Int) -> List(List(Bool)) {
  case rows {
    [] -> []
    [first, ..] -> {
      let width = list.length(first) + 2 * by
      let side = list.repeat(False, by)
      let blank = list.repeat(list.repeat(False, width), by)
      let body = list.map(rows, fn(row) { list.flatten([side, row, side]) })
      list.flatten([blank, body, blank])
    }
  }
}

fn read(rows: List(List(Bool))) -> Result(String, Nil) {
  qrkit.decode(rows)
  |> result.map(fn(decoded) { decoded.text })
  |> result.replace_error(Nil)
}

pub fn decoder_reads_the_same_text_after_turning_and_padding_test() -> Nil {
  let quarter = metamon.Transform(name: "rotate 90", apply: rotate_clockwise)
  metamon.forall_morph(
    rows_of(request()),
    [
      metamon.invariant_under(
        name: "rotate 180",
        under: repeat(quarter, "rotate 180", 2),
      ),
      metamon.invariant_under(
        name: "mirror left to right",
        under: metamon.Transform(name: "mirror", apply: fn(rows) {
          list.map(rows, list.reverse)
        }),
      ),
      metamon.invariant_under(
        name: "mirror top to bottom",
        under: metamon.Transform(name: "flip", apply: list.reverse),
      ),
      metamon.invariant_under(
        name: "light quiet zone of 1",
        under: metamon.Transform(name: "pad 1", apply: pad(_, 1)),
      ),
      metamon.invariant_under(
        name: "light quiet zone of 4",
        under: metamon.Transform(name: "pad 4", apply: pad(_, 4)),
      ),
    ],
    read,
  )
}

pub fn decoder_reads_the_same_text_after_a_quarter_turn_test() -> Nil {
  let quarter = metamon.Transform(name: "rotate 90", apply: rotate_clockwise)
  metamon.forall_morph(
    rows_of(request()),
    [
      metamon.invariant_under(name: "rotate 90", under: quarter),
      metamon.invariant_under(
        name: "rotate 270",
        under: repeat(quarter, "rotate 270", 3),
      ),
      metamon.invariant_under(
        name: "mirror on the diagonal",
        under: metamon.Transform(name: "transpose", apply: transpose),
      ),
    ],
    read,
  )
}

pub fn padding_keeps_what_the_decoder_reports_test() -> Nil {
  metamon.forall(
    generator.tuple2(request(), generator.int(generator.range(from: 1, to: 6))),
    fn(input) {
      let #(req, by) = input
      case build(req) {
        Error(_) -> Nil
        Ok(qr) -> {
          let assert Ok(decoded) = qrkit.decode(pad(qr.rows, by))
          assert #(
              decoded.version,
              decoded.symbol,
              decoded.error_correction,
              decoded.mask,
              decoded.errors_corrected,
            )
            == #(qr.version, qr.symbol, qr.error_correction, qr.mask, 0)
        }
      }
    },
  )
}
