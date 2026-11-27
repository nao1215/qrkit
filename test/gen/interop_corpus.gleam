//// Write random qrkit symbols for another decoder to read:
//// `gleam run -m gen/interop_corpus` writes build/interop/qrkit.tsv, one
//// symbol per line as `symbol \t level \t eci \t text (UTF-8 hex) \t rows`,
//// eci being `26` or `-` and rows '1'/'0' strings joined by '/'.
//// scripts/interop.py decodes them with zxing-cpp and zbar. Each run draws a
//// new seed from the clock.

import generators
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import metamon
import metamon/generator
import metamon/generator/seed
import qrkit
import simplifile

const count: Int = 600

const out_dir: String = "build/interop"

pub fn main() -> Nil {
  // Half the Standard QR symbols declare UTF-8 with ECI 26. Micro QR and
  // rMQR have no ECI.
  let cases =
    generator.tuple4(
      generators.text(),
      generators.symbol(),
      generators.ecc(),
      generator.bool(),
    )
  let lines =
    draw(cases, metamon.random_seed(), count, [])
    |> list.filter_map(fn(input) {
      let #(text, symbol, ecc, utf8) = input
      let eci = case utf8, symbol {
        True, qrkit.Standard -> Some(26)
        _, _ -> None
      }
      case
        qrkit.encode_with(
          text,
          qrkit.EncodeOptions(
            ..qrkit.default_encode_options(),
            symbol: symbol,
            error_correction: ecc,
            eci:,
          ),
        )
      {
        Error(_) -> Error(Nil)
        Ok(qr) ->
          Ok(string.join(
            [
              symbol_name(symbol),
              ecc_letter(ecc),
              eci_text(eci),
              bit_array.base16_encode(bit_array.from_string(text)),
              rows_text(qr.rows),
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

fn symbol_name(symbol: qrkit.Symbol) -> String {
  case symbol {
    qrkit.Standard -> "qr"
    qrkit.Micro -> "micro"
    qrkit.Rectangular -> "rmqr"
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

fn eci_text(eci: Option(Int)) -> String {
  case eci {
    Some(value) -> int.to_string(value)
    None -> "-"
  }
}

fn ecc_letter(ecc: qrkit.ErrorCorrection) -> String {
  case ecc {
    qrkit.Low -> "L"
    qrkit.Medium -> "M"
    qrkit.Quartile -> "Q"
    qrkit.High -> "H"
  }
}
