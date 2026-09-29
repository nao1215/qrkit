//// Write random qrkit symbols for another decoder to read:
//// `gleam run -m gen/interop_corpus` writes build/interop/qrkit.tsv, one
//// symbol per line as `symbol \t level \t text (UTF-8 hex) \t rows`, rows
//// being '1'/'0' strings joined by '/'. scripts/interop.py decodes them with
//// zxing-cpp. Each run draws a new seed from the clock.

import generators
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import metamon
import metamon/generator
import metamon/generator/seed
import qrkit
import qrkit/types
import simplifile

const count: Int = 600

const out_dir: String = "build/interop"

pub fn main() -> Nil {
  let cases =
    generator.tuple3(generators.text(), generators.symbol(), generators.ecc())
  let lines =
    draw(cases, metamon.random_seed(), count, [])
    |> list.filter_map(fn(input) {
      let #(text, symbol, ecc) = input
      case
        qrkit.new(text)
        |> qrkit.with_symbol(symbol)
        |> qrkit.with_ecc(ecc)
        |> qrkit.build
      {
        Error(_) -> Error(Nil)
        Ok(qr) ->
          Ok(string.join(
            [
              symbol_name(symbol),
              qrkit.error_correction_designator(ecc),
              bit_array.base16_encode(bit_array.from_string(text)),
              rows_text(qrkit.rows(qr)),
            ],
            "\t",
          ))
      }
    })
  let assert Ok(Nil) = simplifile.create_directory_all(out_dir)
  let assert Ok(Nil) =
    simplifile.write(out_dir <> "/qrkit.tsv", string.join(lines, "\n") <> "\n")
  io.println(
    "wrote " <> int.to_string(list.length(lines)) <> " symbols to " <> out_dir,
  )
}

fn draw(
  g: generator.Generator(a),
  s: seed.Seed,
  remaining: Int,
  acc: List(a),
) -> List(a) {
  case remaining <= 0 {
    True -> acc
    False -> {
      let #(left, right) = seed.split(s)
      draw(g, right, remaining - 1, [
        generator.generate(g, left, 50).value,
        ..acc
      ])
    }
  }
}

fn symbol_name(symbol: types.Symbol) -> String {
  case symbol {
    types.Standard -> "qr"
    types.Micro -> "micro"
    types.Rectangular -> "rmqr"
  }
}

fn rows_text(rows: List(List(Bool))) -> String {
  rows
  |> list.map(fn(row) {
    list.map(row, fn(dark) {
      case dark {
        True -> "1"
        False -> "0"
      }
    })
    |> string.concat
  })
  |> string.join("/")
}
