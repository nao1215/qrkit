//// Decode a QR module matrix back into text.
////
//// `from_rows` reads a Standard QR, Micro QR or rMQR symbol given as rows of
//// modules (`True` is dark), the shape `qrkit.rows` returns. A light quiet
//// zone around the symbol is removed first, and the symbol may be rotated or
//// mirrored. Damaged codewords are repaired with Reed-Solomon error
//// correction up to the level's capacity.
////
//// This reads a grid of modules, not a photo: locating a symbol in a camera
//// image, perspective correction and thresholding are out of scope.
////
//// ```gleam
//// import qrkit
//// import qrkit/decode
////
//// pub fn round_trip() -> Result(String, Nil) {
////   let assert Ok(qr) = qrkit.encode("https://example.com")
////   case decode.from_rows(qrkit.rows(qr)) {
////     Ok(decoded) -> Ok(decode.text(decoded))
////     Error(_) -> Error(Nil)
////   }
//// }
//// ```

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import qrkit/error.{
  type DecodeError, MalformedData, NotASymbol, TooManyErrors,
  UnreadableFormatInformation,
}
import qrkit/internal/format_info
import qrkit/internal/mask
import qrkit/internal/micro
import qrkit/internal/mode
import qrkit/internal/reed_solomon
import qrkit/internal/rmqr
import qrkit/internal/standard
import qrkit/internal/version
import qrkit/types.{
  type ErrorCorrection, type Mode, type Symbol, Alphanumeric, Byte, Kanji,
  Numeric,
}

/// The Structured Append header of a symbol that is one part of a split
/// message: its 0-based `position`, the `total` number of symbols, and the
/// `parity` byte of the whole message.
pub type StructuredAppend {
  StructuredAppend(position: Int, total: Int, parity: Int)
}

/// A decoded symbol.
pub opaque type Decoded {
  Decoded(
    text: String,
    symbol: Symbol,
    version: Int,
    error_correction: ErrorCorrection,
    mask: Int,
    errors_corrected: Int,
    eci: Option(Int),
    structured_append: Option(StructuredAppend),
  )
}

/// The decoded message.
pub fn text(decoded: Decoded) -> String {
  decoded.text
}

/// The symbol family that was read.
pub fn symbol(decoded: Decoded) -> Symbol {
  decoded.symbol
}

/// The version: 1..40 for Standard QR, 1..4 for Micro QR (M1..M4), 1..32 for
/// rMQR (R7x43..R17x139), numbered as `qrkit.version` numbers them.
pub fn version(decoded: Decoded) -> Int {
  decoded.version
}

/// The error correction level from the format information.
pub fn error_correction(decoded: Decoded) -> ErrorCorrection {
  decoded.error_correction
}

/// The data mask from the format information (always 4 for rMQR, whose mask
/// is fixed).
pub fn mask(decoded: Decoded) -> Int {
  decoded.mask
}

/// How many codewords Reed-Solomon error correction repaired.
pub fn errors_corrected(decoded: Decoded) -> Int {
  decoded.errors_corrected
}

/// The last ECI designator in the data, if any.
pub fn eci(decoded: Decoded) -> Option(Int) {
  decoded.eci
}

/// The Structured Append header, if the symbol is part of a split message.
pub fn structured_append(decoded: Decoded) -> Option(StructuredAppend) {
  decoded.structured_append
}

/// Decode a symbol given as rows of modules, `True` for dark.
pub fn from_rows(rows: List(List(Bool))) -> Result(Decoded, DecodeError) {
  let trimmed = trim_quiet_zone(rows)
  case dimensions(trimmed) {
    Error(error) -> Error(error)
    Ok(#(width, height)) -> {
      let candidates = case width == height {
        True -> square_orientations(trimmed)
        False -> rectangular_orientations(trimmed)
      }
      first_success(candidates, fn(candidate) {
        decode_grid(Grid(
          width_of(candidate),
          list.length(candidate),
          dark_set(candidate),
        ))
      })
    }
  }
}

// --- Geometry --------------------------------------------------------------

type Grid {
  Grid(width: Int, height: Int, dark: set.Set(Int))
}

fn module(grid: Grid) -> fn(Int, Int) -> Bool {
  fn(row, col) { set.contains(grid.dark, row * grid.width + col) }
}

fn dark_set(rows: List(List(Bool))) -> set.Set(Int) {
  let width = width_of(rows)
  list.index_fold(rows, set.new(), fn(acc, row, r) {
    list.index_fold(row, acc, fn(acc2, dark, c) {
      case dark {
        True -> set.insert(acc2, r * width + c)
        False -> acc2
      }
    })
  })
}

fn width_of(rows: List(List(Bool))) -> Int {
  case rows {
    [first, ..] -> list.length(first)
    [] -> 0
  }
}

fn dimensions(rows: List(List(Bool))) -> Result(#(Int, Int), DecodeError) {
  let width = width_of(rows)
  let height = list.length(rows)
  case width > 0 && list.all(rows, fn(row) { list.length(row) == width }) {
    True -> Ok(#(width, height))
    False -> Error(NotASymbol(width, height))
  }
}

fn trim_quiet_zone(rows: List(List(Bool))) -> List(List(Bool)) {
  let light = fn(row) { !list.any(row, fn(dark) { dark }) }
  let trimmed_rows =
    rows
    |> list.drop_while(light)
    |> list.reverse
    |> list.drop_while(light)
    |> list.reverse
  case trimmed_rows {
    [] -> []
    _ -> transpose(transpose(trimmed_rows) |> trim_rows(light))
  }
}

fn trim_rows(
  rows: List(List(Bool)),
  light: fn(List(Bool)) -> Bool,
) -> List(List(Bool)) {
  rows
  |> list.drop_while(light)
  |> list.reverse
  |> list.drop_while(light)
  |> list.reverse
}

fn transpose(rows: List(List(Bool))) -> List(List(Bool)) {
  list.transpose(rows)
}

fn square_orientations(rows: List(List(Bool))) -> List(List(List(Bool))) {
  let rotate = fn(r) { transpose(r) |> list.map(list.reverse) }
  let r90 = rotate(rows)
  let r180 = rotate(r90)
  let r270 = rotate(r180)
  let mirrored = transpose(rows)
  [
    rows,
    r90,
    r180,
    r270,
    mirrored,
    rotate(mirrored),
    rotate(rotate(mirrored)),
    rotate(rotate(rotate(mirrored))),
  ]
}

fn rectangular_orientations(rows: List(List(Bool))) -> List(List(List(Bool))) {
  let flip_vertical = list.reverse
  let flip_horizontal = fn(r) { list.map(r, list.reverse) }
  [
    rows,
    flip_horizontal(flip_vertical(rows)),
    flip_horizontal(rows),
    flip_vertical(rows),
  ]
}

/// Return the first success; otherwise the error of the first candidate,
/// which is the orientation the caller supplied.
fn first_success(
  candidates: List(a),
  attempt: fn(a) -> Result(b, DecodeError),
) -> Result(b, DecodeError) {
  case candidates {
    [] -> Error(UnreadableFormatInformation)
    [first, ..rest] ->
      case attempt(first) {
        Ok(value) -> Ok(value)
        Error(error) ->
          list.fold_until(rest, Error(error), fn(acc, candidate) {
            case attempt(candidate) {
              Ok(value) -> list.Stop(Ok(value))
              Error(_) -> list.Continue(acc)
            }
          })
      }
  }
}

// --- Symbol families -------------------------------------------------------

fn decode_grid(grid: Grid) -> Result(Decoded, DecodeError) {
  let Grid(width, height, _) = grid
  case width == height, rmqr.index_for_size(width, height) {
    True, _ ->
      case width >= 21 && width <= 177 && { width - 17 } % 4 == 0 {
        True -> decode_standard(grid)
        False ->
          case width >= 11 && width <= 17 && width % 2 == 1 {
            True -> decode_micro(grid)
            False -> Error(NotASymbol(width, height))
          }
      }
    False, Ok(index) -> decode_rmqr(grid, index)
    False, Error(Nil) -> Error(NotASymbol(width, height))
  }
}

fn decode_standard(grid: Grid) -> Result(Decoded, DecodeError) {
  let size = grid.width
  let symbol_version = { size - 17 } / 4
  let #(first, second) = standard.read_format_copies(module(grid), size)
  use #(ecc, mask_number) <- result.try(
    format_info.decode_format(first, second)
    |> result.replace_error(UnreadableFormatInformation),
  )
  let bits =
    read_bits(grid, standard.data_module_positions(symbol_version), fn(r, c) {
      mask.mask_at(mask_number, r, c)
    })
  let total = version.total_codewords(symbol_version) |> result.unwrap(0)
  let data_count =
    version.data_codewords(symbol_version, ecc) |> result.unwrap(0)
  let blocks = version.ec_blocks(symbol_version, ecc) |> result.unwrap(1)
  use #(data, corrected) <- result.try(correct_blocks(
    to_bytes(list.take(bits, total * 8)),
    total,
    data_count,
    blocks,
  ))
  use parsed <- result.try(parse(
    bytes_to_bits(data),
    standard_profile(symbol_version),
  ))
  Ok(Decoded(
    parsed.text,
    types.Standard,
    symbol_version,
    ecc,
    mask_number,
    corrected,
    parsed.eci,
    parsed.structured_append,
  ))
}

fn decode_micro(grid: Grid) -> Result(Decoded, DecodeError) {
  use #(symbol_version, ecc, mask_number) <- result.try(
    micro.decode_format(micro.read_format(module(grid)))
    |> result.replace_error(UnreadableFormatInformation),
  )
  case micro.symbol_size(symbol_version) == Ok(grid.width) {
    False -> Error(UnreadableFormatInformation)
    True -> {
      let bits =
        read_bits(grid, micro.data_module_positions(symbol_version), fn(r, c) {
          micro.mask_at(mask_number, r, c)
        })
      let data_bits =
        micro.data_capacity_bits(symbol_version, ecc) |> result.unwrap(0)
      let ec_count = micro.ec_codewords(symbol_version, ecc) |> result.unwrap(0)
      let #(data_part, rest) = list.split(bits, data_bits)
      // A half codeword (M1, M3-L, M3-M) carries its 4 bits in the high
      // nibble, as the encoder computed the error correction over it.
      let padded_data =
        list.append(data_part, list.repeat(False, { 8 - data_bits % 8 } % 8))
      let data_codewords = to_bytes(padded_data)
      let received =
        list.append(data_codewords, to_bytes(list.take(rest, ec_count * 8)))
      use #(block, corrected) <- result.try(
        reed_solomon.correct(received, ec_count)
        |> result.replace_error(TooManyErrors),
      )
      let data =
        list.take(block, list.length(data_codewords))
        |> bytes_to_bits
        |> list.take(data_bits)
      use parsed <- result.try(parse(data, micro_profile(symbol_version)))
      Ok(Decoded(
        parsed.text,
        types.Micro,
        symbol_version,
        ecc,
        mask_number,
        corrected,
        parsed.eci,
        parsed.structured_append,
      ))
    }
  }
}

fn decode_rmqr(grid: Grid, index: Int) -> Result(Decoded, DecodeError) {
  let #(left, right) = rmqr.read_format(module(grid), grid.width, grid.height)
  use #(format_index, ecc) <- result.try(
    rmqr.decode_format(left, right)
    |> result.replace_error(UnreadableFormatInformation),
  )
  case format_index == index {
    False -> Error(UnreadableFormatInformation)
    True -> {
      let bits =
        read_bits(grid, rmqr.data_module_positions(index), rmqr.mask_at)
      let total = rmqr.total_codewords(index)
      use #(data, corrected) <- result.try(correct_blocks(
        to_bytes(list.take(bits, total * 8)),
        total,
        rmqr.data_codewords(index, ecc),
        rmqr.ec_block_count(index, ecc),
      ))
      use parsed <- result.try(parse(bytes_to_bits(data), rmqr_profile(index)))
      Ok(Decoded(
        parsed.text,
        types.Rectangular,
        index + 1,
        ecc,
        4,
        corrected,
        parsed.eci,
        parsed.structured_append,
      ))
    }
  }
}

fn read_bits(
  grid: Grid,
  positions: List(#(Int, Int)),
  mask_at: fn(Int, Int) -> Bool,
) -> List(Bool) {
  let at = module(grid)
  list.map(positions, fn(position) {
    let #(row, col) = position
    at(row, col) != mask_at(row, col)
  })
}

fn correct_blocks(
  codewords: List(Int),
  total: Int,
  data_count: Int,
  blocks: Int,
) -> Result(#(List(Int), Int), DecodeError) {
  let ec_count = total / blocks - data_count / blocks
  reed_solomon.deinterleave(
    codewords,
    total_codewords: total,
    data_codewords: data_count,
    blocks: blocks,
  )
  |> list.try_fold(#([], 0), fn(acc, block) {
    case reed_solomon.correct(block, ec_count) {
      Ok(#(fixed, count)) ->
        Ok(#(
          list.append(acc.0, list.take(fixed, list.length(fixed) - ec_count)),
          acc.1 + count,
        ))
      Error(Nil) -> Error(TooManyErrors)
    }
  })
}

fn to_bytes(bits: List(Bool)) -> List(Int) {
  list.sized_chunk(bits, 8)
  |> list.filter(fn(chunk) { list.length(chunk) == 8 })
  |> list.map(bits_to_int)
}

fn bits_to_int(bits: List(Bool)) -> Int {
  list.fold(bits, 0, fn(acc, bit) {
    acc
    * 2
    + case bit {
      True -> 1
      False -> 0
    }
  })
}

fn bytes_to_bits(bytes: List(Int)) -> List(Bool) {
  list.flat_map(bytes, fn(byte) {
    [7, 6, 5, 4, 3, 2, 1, 0]
    |> list.map(fn(shift) {
      int.bitwise_and(int.bitwise_shift_right(byte, shift), 1) == 1
    })
  })
}

// --- Bit stream ------------------------------------------------------------

/// What a mode indicator announces.
type Segment {
  DataSegment(Mode)
  EciSegment
  StructuredAppendSegment
  Fnc1First
  Fnc1Second
  End
}

type Profile {
  Profile(
    indicator_bits: Int,
    terminator_bits: Int,
    segment: fn(Int) -> Result(Segment, Nil),
    count_bits: fn(Mode) -> Result(Int, Nil),
  )
}

fn standard_profile(symbol_version: Int) -> Profile {
  Profile(
    indicator_bits: 4,
    terminator_bits: 4,
    segment: fn(value) {
      case value {
        0b0000 -> Ok(End)
        0b0001 -> Ok(DataSegment(Numeric))
        0b0010 -> Ok(DataSegment(Alphanumeric))
        0b0100 -> Ok(DataSegment(Byte))
        0b1000 -> Ok(DataSegment(Kanji))
        0b0111 -> Ok(EciSegment)
        0b0011 -> Ok(StructuredAppendSegment)
        0b0101 -> Ok(Fnc1First)
        0b1001 -> Ok(Fnc1Second)
        _ -> Error(Nil)
      }
    },
    count_bits: fn(m) { Ok(mode.char_count_bits(m, symbol_version)) },
  )
}

fn micro_profile(symbol_version: Int) -> Profile {
  Profile(
    indicator_bits: micro.mode_indicator_bits(symbol_version),
    terminator_bits: symbol_version * 2 + 1,
    segment: fn(value) {
      case value {
        0 -> Ok(DataSegment(Numeric))
        1 -> Ok(DataSegment(Alphanumeric))
        2 -> Ok(DataSegment(Byte))
        3 -> Ok(DataSegment(Kanji))
        _ -> Error(Nil)
      }
    },
    count_bits: fn(m) {
      micro.char_count_bits_for_mode(m, symbol_version)
      |> result.replace_error(Nil)
    },
  )
}

fn rmqr_profile(index: Int) -> Profile {
  Profile(
    indicator_bits: 3,
    terminator_bits: 3,
    segment: fn(value) {
      case value {
        0b000 -> Ok(End)
        0b001 -> Ok(DataSegment(Numeric))
        0b010 -> Ok(DataSegment(Alphanumeric))
        0b011 -> Ok(DataSegment(Byte))
        0b100 -> Ok(DataSegment(Kanji))
        0b101 -> Ok(Fnc1First)
        0b110 -> Ok(Fnc1Second)
        _ -> Ok(EciSegment)
      }
    },
    count_bits: fn(m) { Ok(rmqr.count_bits(m, index)) },
  )
}

type Parsed {
  Parsed(
    text: String,
    eci: Option(Int),
    structured_append: Option(StructuredAppend),
  )
}

type State {
  State(
    pieces: List(String),
    pending_bytes: List(Int),
    eci: Option(Int),
    structured_append: Option(StructuredAppend),
  )
}

fn parse(bits: List(Bool), profile: Profile) -> Result(Parsed, DecodeError) {
  use state <- result.try(parse_segments(
    bits,
    profile,
    State([], [], None, None),
  ))
  let State(pieces, _, eci, structured_append) = flush_bytes(state)
  Ok(Parsed(string.concat(list.reverse(pieces)), eci, structured_append))
}

fn parse_segments(
  bits: List(Bool),
  profile: Profile,
  state: State,
) -> Result(State, DecodeError) {
  let remaining = list.length(bits)
  let at_end =
    remaining < profile.terminator_bits
    || list.all(list.take(bits, profile.terminator_bits), fn(bit) { !bit })
  case remaining == 0 || at_end {
    True -> Ok(state)
    False -> {
      let #(indicator, rest) = list.split(bits, profile.indicator_bits)
      case profile.segment(bits_to_int(indicator)) {
        Error(Nil) ->
          Error(MalformedData(
            "unknown mode indicator " <> int.to_string(bits_to_int(indicator)),
          ))
        Ok(End) -> Ok(state)
        Ok(Fnc1First) -> parse_segments(rest, profile, state)
        Ok(Fnc1Second) -> {
          use #(_, after) <- result.try(take_int(rest, 8, "FNC1 indicator"))
          parse_segments(after, profile, state)
        }
        Ok(EciSegment) -> {
          use #(designator, after) <- result.try(read_eci(rest))
          parse_segments(
            after,
            profile,
            State(..flush_bytes(state), eci: Some(designator)),
          )
        }
        Ok(StructuredAppendSegment) -> {
          use #(position, after1) <- result.try(take_int(
            rest,
            4,
            "Structured Append",
          ))
          use #(total, after2) <- result.try(take_int(
            after1,
            4,
            "Structured Append",
          ))
          use #(parity, after3) <- result.try(take_int(
            after2,
            8,
            "Structured Append",
          ))
          parse_segments(
            after3,
            profile,
            State(
              ..state,
              structured_append: Some(StructuredAppend(
                position,
                total + 1,
                parity,
              )),
            ),
          )
        }
        Ok(DataSegment(segment_mode)) -> {
          use width <- result.try(
            profile.count_bits(segment_mode)
            |> result.replace_error(MalformedData(
              "mode not allowed in this version",
            )),
          )
          use #(count, after) <- result.try(take_int(
            rest,
            width,
            "character count",
          ))
          use #(next_state, after_data) <- result.try(read_data(
            segment_mode,
            count,
            after,
            state,
          ))
          parse_segments(after_data, profile, next_state)
        }
      }
    }
  }
}

fn read_data(
  segment_mode: Mode,
  count: Int,
  bits: List(Bool),
  state: State,
) -> Result(#(State, List(Bool)), DecodeError) {
  case segment_mode {
    Byte -> {
      use #(bytes, rest) <- result.try(take_values(bits, count, 8, "Byte"))
      Ok(#(
        State(..state, pending_bytes: list.append(state.pending_bytes, bytes)),
        rest,
      ))
    }
    Numeric -> {
      use #(digits, rest) <- result.try(read_numeric(bits, count, ""))
      Ok(#(push(state, digits), rest))
    }
    Alphanumeric -> {
      use #(text, rest) <- result.try(read_alphanumeric(bits, count, ""))
      Ok(#(push(state, text), rest))
    }
    Kanji -> {
      use #(values, rest) <- result.try(take_values(bits, count, 13, "Kanji"))
      use text <- result.try(
        list.try_map(values, kanji_character) |> result.map(string.concat),
      )
      Ok(#(push(state, text), rest))
    }
  }
}

fn push(state: State, text: String) -> State {
  let flushed = flush_bytes(state)
  State(..flushed, pieces: [text, ..flushed.pieces])
}

fn flush_bytes(state: State) -> State {
  case state.pending_bytes {
    [] -> state
    bytes ->
      State(
        ..state,
        pieces: [bytes_to_text(bytes, state.eci), ..state.pieces],
        pending_bytes: [],
      )
  }
}

fn read_numeric(
  bits: List(Bool),
  count: Int,
  acc: String,
) -> Result(#(String, List(Bool)), DecodeError) {
  case count {
    0 -> Ok(#(acc, bits))
    _ -> {
      let #(digits, width) = case count {
        1 -> #(1, 4)
        2 -> #(2, 7)
        _ -> #(3, 10)
      }
      use #(value, rest) <- result.try(take_int(bits, width, "Numeric"))
      case value < power_of_ten(digits) {
        False -> Error(MalformedData("Numeric group out of range"))
        True ->
          read_numeric(
            rest,
            count - digits,
            acc <> string.pad_start(int.to_string(value), digits, "0"),
          )
      }
    }
  }
}

fn power_of_ten(digits: Int) -> Int {
  case digits {
    1 -> 10
    2 -> 100
    _ -> 1000
  }
}

const alphanumeric_table: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

fn read_alphanumeric(
  bits: List(Bool),
  count: Int,
  acc: String,
) -> Result(#(String, List(Bool)), DecodeError) {
  case count {
    0 -> Ok(#(acc, bits))
    1 -> {
      use #(value, rest) <- result.try(take_int(bits, 6, "Alphanumeric"))
      use char <- result.try(alphanumeric_char(value))
      Ok(#(acc <> char, rest))
    }
    _ -> {
      use #(value, rest) <- result.try(take_int(bits, 11, "Alphanumeric"))
      use first <- result.try(alphanumeric_char(value / 45))
      use second <- result.try(alphanumeric_char(value % 45))
      read_alphanumeric(rest, count - 2, acc <> first <> second)
    }
  }
}

fn alphanumeric_char(value: Int) -> Result(String, DecodeError) {
  case value < 45 {
    True -> Ok(string.slice(alphanumeric_table, value, 1))
    False -> Error(MalformedData("Alphanumeric value out of range"))
  }
}

fn kanji_character(value: Int) -> Result(String, DecodeError) {
  let combined = { value / 0xC0 } * 256 + value % 0xC0
  let sjis = case combined < 0x1F00 {
    True -> combined + 0x8140
    False -> combined + 0xC140
  }
  case mode.sjis_to_codepoint(sjis) {
    Ok(codepoint) -> codepoint_string(codepoint)
    Error(Nil) -> Ok("\u{FFFD}")
  }
}

fn codepoint_string(codepoint: Int) -> Result(String, DecodeError) {
  case string.utf_codepoint(codepoint) {
    Ok(cp) -> Ok(string.from_utf_codepoints([cp]))
    Error(Nil) -> Error(MalformedData("invalid code point"))
  }
}

/// Interpret Byte-mode data under the active ECI: Shift JIS for 20,
/// ISO-8859-1 for 1 and 3, UTF-8 for 26. Without an ECI the character set is
/// guessed with zxing's rules: UTF-8 when the bytes are valid UTF-8 with a
/// multi-byte character (what qrkit and most encoders write); Shift JIS when
/// they are valid Shift JIS with a run of three double-byte or half-width
/// katakana characters; otherwise ISO-8859-1 (the standard's default) when
/// the bytes allow it, and Shift JIS when only that fits.
fn bytes_to_text(bytes: List(Int), eci: Option(Int)) -> String {
  let data = list.fold(bytes, <<>>, fn(acc, b) { <<acc:bits, b>> })
  case eci, bit_array.to_string(data) {
    Some(20), _ -> shift_jis_text(bytes, "")
    Some(1), _ | Some(3), _ -> latin1_text(bytes)
    Some(26), Ok(text) -> text
    Some(26), Error(Nil) -> latin1_text(bytes)
    _, Ok(text) -> text
    _, Error(Nil) ->
      case guess_shift_jis(bytes) {
        True -> shift_jis_text(bytes, "")
        False -> latin1_text(bytes)
      }
  }
}

type SjisStats {
  SjisStats(
    valid: Bool,
    double_run: Int,
    longest_double_run: Int,
    katakana_run: Int,
    longest_katakana_run: Int,
    katakana: Int,
  )
}

/// zxing's choice between Shift JIS and ISO-8859-1 for bytes that are not
/// UTF-8.
fn guess_shift_jis(bytes: List(Int)) -> Bool {
  let stats = shift_jis_stats(bytes, SjisStats(True, 0, 0, 0, 0, 0))
  let can_be_latin1 = !list.any(bytes, fn(b) { b >= 0x80 && b < 0xA0 })
  let latin1_high_other =
    list.count(bytes, fn(b) {
      b > 0x9F && { b < 0xC0 || b == 0xD7 || b == 0xF7 }
    })
  case
    stats.valid,
    stats.longest_katakana_run >= 3 || stats.longest_double_run >= 3,
    can_be_latin1
  {
    False, _, _ -> False
    True, True, _ -> True
    True, False, True ->
      { stats.longest_katakana_run == 2 && stats.katakana == 2 }
      || latin1_high_other * 10 >= list.length(bytes)
    True, False, False -> True
  }
}

fn shift_jis_stats(bytes: List(Int), stats: SjisStats) -> SjisStats {
  case bytes {
    [] -> stats
    [lead, trail, ..rest]
      if { lead >= 0x81 && lead <= 0x9F } || { lead >= 0xE0 && lead <= 0xEF }
    ->
      case mode.sjis_to_codepoint(lead * 256 + trail) {
        Ok(_) -> {
          let run = stats.double_run + 1
          shift_jis_stats(
            rest,
            SjisStats(
              ..stats,
              double_run: run,
              longest_double_run: int.max(stats.longest_double_run, run),
              katakana_run: 0,
            ),
          )
        }
        Error(Nil) -> SjisStats(..stats, valid: False)
      }
    [byte, ..rest] if byte >= 0xA1 && byte <= 0xDF -> {
      let run = stats.katakana_run + 1
      shift_jis_stats(
        rest,
        SjisStats(
          ..stats,
          katakana_run: run,
          longest_katakana_run: int.max(stats.longest_katakana_run, run),
          katakana: stats.katakana + 1,
          double_run: 0,
        ),
      )
    }
    [byte, ..rest] if byte < 0x80 ->
      shift_jis_stats(rest, SjisStats(..stats, double_run: 0, katakana_run: 0))
    _ -> SjisStats(..stats, valid: False)
  }
}

fn latin1_text(bytes: List(Int)) -> String {
  list.filter_map(bytes, string.utf_codepoint)
  |> string.from_utf_codepoints
}

fn shift_jis_text(bytes: List(Int), acc: String) -> String {
  case bytes {
    [] -> acc
    [lead, trail, ..rest]
      if { lead >= 0x81 && lead <= 0x9F } || { lead >= 0xE0 && lead <= 0xEF }
    -> {
      let char = case mode.sjis_to_codepoint(lead * 256 + trail) {
        Ok(cp) -> result.unwrap(codepoint_string(cp), "\u{FFFD}")
        Error(Nil) -> "\u{FFFD}"
      }
      shift_jis_text(rest, acc <> char)
    }
    [byte, ..rest] if byte >= 0xA1 && byte <= 0xDF ->
      shift_jis_text(
        rest,
        acc <> result.unwrap(codepoint_string(0xFF61 + byte - 0xA1), "\u{FFFD}"),
      )
    [byte, ..rest] if byte < 0x80 ->
      shift_jis_text(
        rest,
        acc <> result.unwrap(codepoint_string(byte), "\u{FFFD}"),
      )
    [_, ..rest] -> shift_jis_text(rest, acc <> "\u{FFFD}")
  }
}

fn read_eci(bits: List(Bool)) -> Result(#(Int, List(Bool)), DecodeError) {
  case bits {
    [False, ..rest] -> take_int(rest, 7, "ECI")
    [True, False, ..rest] -> take_int(rest, 14, "ECI")
    [True, True, False, ..rest] -> take_int(rest, 21, "ECI")
    _ -> Error(MalformedData("invalid ECI designator"))
  }
}

fn take_int(
  bits: List(Bool),
  width: Int,
  what: String,
) -> Result(#(Int, List(Bool)), DecodeError) {
  let #(head, rest) = list.split(bits, width)
  case list.length(head) == width {
    True -> Ok(#(bits_to_int(head), rest))
    False -> Error(MalformedData(what <> " segment is truncated"))
  }
}

fn take_values(
  bits: List(Bool),
  count: Int,
  width: Int,
  what: String,
) -> Result(#(List(Int), List(Bool)), DecodeError) {
  let #(head, rest) = list.split(bits, count * width)
  case list.length(head) == count * width {
    True -> Ok(#(list.sized_chunk(head, width) |> list.map(bits_to_int), rest))
    False -> Error(MalformedData(what <> " segment is truncated"))
  }
}
