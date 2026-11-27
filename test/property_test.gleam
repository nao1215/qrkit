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
  metamon.forall(
    generator.tuple3(generators.text(), generators.symbol(), generators.ecc()),
    fn(input) {
      let #(text, symbol, ecc) = input
      case build(text, symbol, ecc) {
        // Too long for the symbol family and level.
        Error(_) -> metamon.classify(label: "does not fit", when: True)
        Ok(qr) -> {
          let decoded =
            qrkit.decode(qr.rows)
            |> result.map(fn(decoded) {
              #(decoded.text, decoded.symbol, decoded.error_correction)
            })
          assert decoded == Ok(input)
        }
      }
    },
  )
}

pub fn one_damaged_module_is_corrected_test() -> Nil {
  metamon.forall(
    generator.tuple4(
      generators.text(),
      generators.symbol(),
      generators.ecc(),
      generator.int(generator.range(from: 0, to: 1_000_000)),
    ),
    fn(input) {
      let #(text, symbol, ecc, index) = input
      case build(text, symbol, ecc) {
        Error(_) -> Nil
        Ok(qr) -> {
          let target = index % { qr.width * qr.height }
          let damaged = flip(qr.rows, target, qr.width)
          assert result.map(qrkit.decode(damaged), fn(decoded) { decoded.text })
            == Ok(text)
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
        length: generator.range(from: width * height, to: width * height),
      )
      |> generator.map(fn(cells) { list.sized_chunk(cells, width) })
    })
  metamon.forall(grid, fn(rows) {
    let _decoded = qrkit.decode(rows)
    Nil
  })
}

pub fn decoder_returns_for_heavily_damaged_symbols_test() -> Nil {
  metamon.forall(
    generator.tuple3(
      generators.text(),
      generators.symbol(),
      generator.list_of(
        generator.int(generator.range(from: 0, to: 1_000_000)),
        length: generator.range(from: 1, to: 60),
      ),
    ),
    fn(input) {
      let #(text, symbol, targets) = input
      case build(text, symbol, qrkit.Medium) {
        Error(_) -> Nil
        Ok(qr) -> {
          let cells = qr.width * qr.height
          let damaged =
            list.fold(targets, qr.rows, fn(rows, t) {
              flip(rows, t % cells, qr.width)
            })
          let _decoded = qrkit.decode(damaged)
          Nil
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
