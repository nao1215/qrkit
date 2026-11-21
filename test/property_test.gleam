//// Property tests: encode then decode returns the input for every symbol
//// family and level, a single damaged module is always corrected, and the
//// decoder returns a value (never crashes) for arbitrary grids.
////
//// The nightly workflow runs these with METAMON_RUNS_MULTIPLIER to explore
//// many more inputs than a pull request does.

import generators
import gleam/list
import gleam/result
import metamon
import metamon/generator
import metamon/generator/range
import qrkit

fn build(
  text: String,
  symbol: qrkit.Symbol,
  ecc: qrkit.ErrorCorrection,
) -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.encode_with(
    text,
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: symbol,
      error_correction: ecc,
    ),
  )
}

pub fn encode_then_decode_round_trips_test() -> Nil {
  metamon.forall_round_trip_partial(
    gen: generator.tuple3(
      generators.text(),
      generators.symbol(),
      generators.ecc(),
    ),
    name: "encode_then_decode",
    encode: fn(input) {
      let #(text, symbol, ecc) = input
      build(text, symbol, ecc) |> result.map(fn(qr) { qr.rows })
    },
    decode: fn(rows) {
      qrkit.decode(rows)
      |> result.map(fn(decoded) {
        #(decoded.text, decoded.symbol, decoded.error_correction)
      })
    },
  )
}

pub fn one_damaged_module_is_corrected_test() -> Nil {
  metamon.forall(
    generator.tuple4(
      generators.text(),
      generators.symbol(),
      generators.ecc(),
      generator.non_negative_int(),
    ),
    fn(input) {
      let #(text, symbol, ecc, index) = input
      case build(text, symbol, ecc) {
        Error(_) -> True
        Ok(qr) -> {
          let target = index % { qr.width * qr.height }
          let damaged = flip(qr.rows, target, qr.width)
          case qrkit.decode(damaged) {
            Ok(decoded) -> decoded.text == text
            Error(_) -> False
          }
        }
      }
    },
  )
}

pub fn decoder_returns_for_arbitrary_grids_test() -> Nil {
  let grid =
    generator.element_of([
      #(21, 21),
      #(25, 25),
      #(11, 11),
      #(15, 15),
      #(43, 7),
      #(27, 13),
    ])
    |> generator.bind(fn(size) {
      let #(width, height) = size
      generator.list_of(
        generator.bool(),
        range.constant(width * height, width * height),
      )
      |> generator.map(fn(cells) { list.sized_chunk(cells, width) })
    })
  metamon.forall(grid, fn(rows) {
    case qrkit.decode(rows) {
      Ok(_) -> True
      Error(_) -> True
    }
  })
}

pub fn decoder_returns_for_heavily_damaged_symbols_test() -> Nil {
  metamon.forall(
    generator.tuple3(
      generators.text(),
      generators.symbol(),
      generator.list_of(generator.non_negative_int(), range.constant(1, 60)),
    ),
    fn(input) {
      let #(text, symbol, targets) = input
      case build(text, symbol, qrkit.Medium) {
        Error(_) -> True
        Ok(qr) -> {
          let cells = qr.width * qr.height
          let damaged =
            list.fold(targets, qr.rows, fn(rows, t) {
              flip(rows, t % cells, qr.width)
            })
          case qrkit.decode(damaged) {
            Ok(_) -> True
            Error(_) -> True
          }
        }
      }
    },
  )
}

fn flip(rows: List(List(Bool)), target: Int, width: Int) -> List(List(Bool)) {
  list.index_map(rows, fn(row, r) {
    list.index_map(row, fn(dark, c) {
      case r * width + c == target {
        True -> !dark
        False -> dark
      }
    })
  })
}
