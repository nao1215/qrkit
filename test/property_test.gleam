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
import qrkit/decode
import qrkit/types

fn build(
  text: String,
  symbol: types.Symbol,
  ecc: types.ErrorCorrection,
) -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.new(text)
  |> qrkit.with_symbol(symbol)
  |> qrkit.with_ecc(ecc)
  |> qrkit.build
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
      build(text, symbol, ecc) |> result.map(qrkit.rows)
    },
    decode: fn(rows) {
      decode.from_rows(rows)
      |> result.map(fn(decoded) {
        #(
          decode.text(decoded),
          decode.symbol(decoded),
          decode.error_correction(decoded),
        )
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
          let target = index % { qrkit.width(qr) * qrkit.height(qr) }
          let damaged = flip(qrkit.rows(qr), target, qrkit.width(qr))
          case decode.from_rows(damaged) {
            Ok(decoded) -> decode.text(decoded) == text
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
    case decode.from_rows(rows) {
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
      case build(text, symbol, types.Medium) {
        Error(_) -> True
        Ok(qr) -> {
          let cells = qrkit.width(qr) * qrkit.height(qr)
          let damaged =
            list.fold(targets, qrkit.rows(qr), fn(rows, t) {
              flip(rows, t % cells, qrkit.width(qr))
            })
          case decode.from_rows(damaged) {
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
