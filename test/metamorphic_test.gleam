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
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform
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

fn append(suffix: String) -> transform.Transform(Request) {
  transform.new("append " <> suffix, fn(input: Request) {
    let #(text, symbol, ecc) = input
    #(text <> suffix, symbol, ecc)
  })
}

pub fn longer_payload_never_gets_a_smaller_symbol_test() -> Nil {
  let grows = relation.new("not smaller", not_larger)
  metamon.forall_morphs(
    request(),
    list.map(["7", "Z", "z", "漢", "é"], fn(suffix) {
      metamon.mr(
        name: "append " <> suffix,
        transform: append(suffix),
        relation: grows,
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
      #(3, generator.ascii_digit()),
      #(2, generator.ascii_upper()),
      #(1, generator.ascii_printable()),
    ])
  generator.tuple3(
    generator.string(char, range.constant(150, 500)),
    generator.return(qrkit.Standard),
    generators.ecc(),
  )
}

/// Each run builds two symbols of version 10 to 30, so this test keeps its
/// own small run count: the nightly job multiplies it by 10 and eunit stops a
/// test after 5 seconds.
pub fn longer_long_payload_never_gets_a_smaller_symbol_test() -> Nil {
  let cfg = metamon.default_config() |> metamon.with_runs_or_panic(10)
  metamon.forall_morph_with(
    cfg,
    long_request(),
    metamon.mr(
      name: "append 7",
      transform: append("7"),
      relation: relation.new("not smaller", not_larger),
    ),
    modules,
  )
}

pub fn stronger_error_correction_never_gets_a_smaller_symbol_test() -> Nil {
  metamon.forall_morph(
    request(),
    metamon.mr(
      name: "raise error correction one level",
      transform: transform.new("stronger", stronger),
      relation: relation.new("not smaller", not_larger),
    ),
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
  let quarter = transform.new("rotate 90", rotate_clockwise)
  metamon.forall_morphs(
    rows_of(request()),
    [
      metamon.invariant_under(
        name: "rotate 180",
        under: transform.repeat(quarter, times: 2),
      ),
      metamon.invariant_under(
        name: "mirror left to right",
        under: transform.new("mirror", fn(rows) { list.map(rows, list.reverse) }),
      ),
      metamon.invariant_under(
        name: "mirror top to bottom",
        under: transform.new("flip", list.reverse),
      ),
      metamon.invariant_under(
        name: "light quiet zone of 1",
        under: transform.new("pad 1", fn(rows) { pad(rows, 1) }),
      ),
      metamon.invariant_under(
        name: "light quiet zone of 4",
        under: transform.new("pad 4", fn(rows) { pad(rows, 4) }),
      ),
    ],
    read,
  )
}

pub fn decoder_reads_the_same_text_after_a_quarter_turn_test() -> Nil {
  let quarter = transform.new("rotate 90", rotate_clockwise)
  metamon.forall_morphs(
    rows_of(request()),
    [
      metamon.invariant_under(name: "rotate 90", under: quarter),
      metamon.invariant_under(
        name: "rotate 270",
        under: transform.repeat(quarter, times: 3),
      ),
      metamon.invariant_under(
        name: "mirror on the diagonal",
        under: transform.new("transpose", transpose),
      ),
    ],
    read,
  )
}

pub fn padding_keeps_what_the_decoder_reports_test() -> Nil {
  metamon.forall(
    generator.tuple2(request(), generator.int(range.constant(1, 6))),
    fn(input) {
      let #(req, by) = input
      case build(req) {
        Error(_) -> True
        Ok(qr) ->
          case qrkit.decode(pad(qr.rows, by)) {
            Ok(decoded) ->
              decoded.version == qr.version
              && decoded.symbol == qr.symbol
              && decoded.error_correction == qr.error_correction
              && decoded.mask == qr.mask
              && decoded.errors_corrected == 0
            Error(_) -> False
          }
      }
    },
  )
}
