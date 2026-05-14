//// Rectangular Micro QR (rMQR) encoder, ISO/IEC 23941:2022.
////
//// Supports the 32 rMQR sizes from R7×43 to R17×139 with M or H error
//// correction. Reuses the standard Reed-Solomon engine and matrix primitives;
//// functional patterns and format info follow ISO/IEC 23941.

import gleam/list
import qrkit/error.{
  type EncodeError, type ErrorCorrection, type Mode, type ModePreference,
  Alphanumeric, Byte, DataExceedsCapacity, High, IncompatibleOptions,
  InvalidVersion, Kanji, Medium, Numeric,
}
import qrkit/internal/bitstream
import qrkit/internal/matrix
import qrkit/internal/mode
import qrkit/internal/reed_solomon
import qrkit/internal/util

pub opaque type Encoded {
  Encoded(version: Int, width: Int, height: Int, rows: List(List(Bool)))
}

pub fn version(encoded: Encoded) -> Int {
  let Encoded(version, _, _, _) = encoded
  version
}

pub fn width(encoded: Encoded) -> Int {
  let Encoded(_, width, _, _) = encoded
  width
}

pub fn height(encoded: Encoded) -> Int {
  let Encoded(_, _, height, _) = encoded
  height
}

pub fn rows(encoded: Encoded) -> List(List(Bool)) {
  let Encoded(_, _, _, rows) = encoded
  rows
}

const total_versions: Int = 32

const heights: List(Int) = [
  7, 7, 7, 7, 7, 9, 9, 9, 9, 9, 11, 11, 11, 11, 11, 11, 13, 13, 13, 13, 13, 13,
  15, 15, 15, 15, 15, 17, 17, 17, 17, 17,
]

const widths: List(Int) = [
  43, 59, 77, 99, 139, 43, 59, 77, 99, 139, 27, 43, 59, 77, 99, 139, 27, 43, 59,
  77, 99, 139, 43, 59, 77, 99, 139, 43, 59, 77, 99, 139,
]

const data_codewords_m: List(Int) = [
  6, 12, 20, 28, 44, 12, 21, 31, 42, 63, 7, 19, 31, 43, 57, 84, 12, 27, 38, 53,
  73, 106, 33, 48, 67, 88, 127, 39, 56, 78, 100, 152,
]

const data_codewords_h: List(Int) = [
  3, 7, 10, 14, 24, 7, 11, 17, 22, 33, 5, 11, 15, 23, 29, 42, 7, 13, 20, 29, 35,
  54, 15, 26, 31, 48, 69, 21, 28, 38, 56, 76,
]

const total_codewords_table: List(Int) = [
  13, 21, 32, 44, 68, 21, 33, 49, 66, 99, 15, 31, 47, 67, 89, 132, 21, 41, 60,
  85, 113, 166, 51, 74, 103, 136, 199, 61, 88, 122, 160, 232,
]

const numeric_cci: List(Int) = [
  4, 5, 6, 7, 7, 5, 6, 7, 7, 8, 4, 6, 7, 7, 8, 8, 5, 6, 7, 7, 8, 8, 7, 7, 8, 8,
  9, 7, 8, 8, 8, 9,
]

const alphanum_cci: List(Int) = [
  3, 5, 5, 6, 6, 5, 5, 6, 6, 7, 4, 5, 6, 6, 7, 7, 5, 6, 6, 7, 7, 8, 6, 7, 7, 7,
  8, 6, 7, 7, 8, 8,
]

const byte_cci: List(Int) = [
  3, 4, 5, 5, 6, 4, 5, 5, 6, 6, 3, 5, 5, 6, 6, 7, 4, 5, 6, 6, 7, 7, 6, 6, 7, 7,
  7, 6, 6, 7, 7, 8,
]

const kanji_cci: List(Int) = [
  2, 3, 4, 5, 5, 3, 4, 5, 5, 6, 2, 4, 5, 5, 6, 6, 3, 5, 5, 6, 6, 7, 5, 5, 6, 6,
  7, 5, 6, 6, 6, 7,
]

const format_info_left: List(Int) = [
  0x1FAB2, 0x1E597, 0x1DBDD, 0x1C4F8, 0x1B86C, 0x1A749, 0x19903, 0x18626,
  0x17F0E, 0x1602B, 0x15E61, 0x14144, 0x13DD0, 0x122F5, 0x11CBF, 0x1039A,
  0x0F1CA, 0x0EEEF, 0x0D0A5, 0x0CF80, 0x0B314, 0x0AC31, 0x0927B, 0x08D5E,
  0x07476, 0x06B53, 0x05519, 0x04A3C, 0x036A8, 0x0298D, 0x017C7, 0x008E2,
  0x3F367, 0x3EC42, 0x3D208, 0x3CD2D, 0x3B1B9, 0x3AE9C, 0x390D6, 0x38FF3,
  0x376DB, 0x369FE, 0x357B4, 0x34891, 0x33405, 0x32B20, 0x3156A, 0x30A4F,
  0x2F81F, 0x2E73A, 0x2D970, 0x2C655, 0x2BAC1, 0x2A5E4, 0x29BAE, 0x2848B,
  0x27DA3, 0x26286, 0x25CCC, 0x243E9, 0x23F7D, 0x22058, 0x21E12, 0x20137,
]

const format_info_right: List(Int) = [
  0x20A7B, 0x2155E, 0x22B14, 0x23431, 0x248A5, 0x25780, 0x269CA, 0x276EF,
  0x28FC7, 0x290E2, 0x2AEA8, 0x2B18D, 0x2CD19, 0x2D23C, 0x2EC76, 0x2F353,
  0x30103, 0x31E26, 0x3206C, 0x33F49, 0x343DD, 0x35CF8, 0x362B2, 0x37D97,
  0x384BF, 0x39B9A, 0x3A5D0, 0x3BAF5, 0x3C661, 0x3D944, 0x3E70E, 0x3F82B,
  0x003AE, 0x01C8B, 0x022C1, 0x03DE4, 0x04170, 0x05E55, 0x0601F, 0x07F3A,
  0x08612, 0x09937, 0x0A77D, 0x0B858, 0x0C4CC, 0x0DBE9, 0x0E5A3, 0x0FA86,
  0x108D6, 0x117F3, 0x129B9, 0x1369C, 0x14A08, 0x1552D, 0x16B67, 0x17442,
  0x18D6A, 0x1924F, 0x1AC05, 0x1B320, 0x1CFB4, 0x1D091, 0x1EEDB, 0x1F1FE,
]

// Indices into rmqr_table_d1 — alignment column centres per width (5 rows × 4)
const alignment_columns: List(Int) = [
  21, 0, 0, 0, 19, 39, 0, 0, 25, 51, 0, 0, 23, 49, 75, 0, 27, 55, 83, 111,
]

/// Encode `text` into an rMQR symbol. `requested_version` is a 1-based index
/// into the 32-version table (`1` = R7×43, `32` = R17×139). The encoder picks
/// the smallest version that fits.
pub fn encode(
  text: String,
  ecc: ErrorCorrection,
  requested_version: Int,
  preference: ModePreference,
) -> Result(Encoded, EncodeError) {
  use _ <- result_try(validate_ecc(ecc))
  use selected_mode <- result_try(select_mode(text, preference))
  let start_index = clamp_version_index(requested_version)
  use chosen <- result_try(find_version(text, selected_mode, ecc, start_index))
  use codewords <- result_try(create_codewords(text, selected_mode, ecc, chosen))
  let h_size = lookup_int(widths, chosen)
  let v_size = lookup_int(heights, chosen)
  let total = lookup_int(total_codewords_table, chosen)
  let final_matrix = build_matrix(chosen, ecc, h_size, v_size, total, codewords)
  Ok(Encoded(chosen + 1, h_size, v_size, matrix.rows(final_matrix)))
}

/// Return `#(width, height)` for a 0-based rMQR version index.
pub fn dimensions(index: Int) -> Result(#(Int, Int), EncodeError) {
  case index >= 0 && index < total_versions {
    True -> Ok(#(lookup_int(widths, index), lookup_int(heights, index)))
    False -> Error(InvalidVersion(index + 1))
  }
}

fn validate_ecc(ecc: ErrorCorrection) -> Result(Nil, EncodeError) {
  case ecc {
    Medium | High -> Ok(Nil)
    _ ->
      Error(IncompatibleOptions(
        "rMQR only supports M or H error correction levels",
      ))
  }
}

fn select_mode(
  text: String,
  preference: ModePreference,
) -> Result(Mode, EncodeError) {
  case preference {
    error.ForceByte -> Ok(Byte)
    error.Auto -> Ok(uniform_mode(util.characters(text), Numeric))
  }
}

fn uniform_mode(chars: List(String), best: Mode) -> Mode {
  case chars {
    [] -> best
    [char, ..rest] -> uniform_mode(rest, refine_mode(best, classify_char(char)))
  }
}

fn classify_char(char: String) -> Mode {
  case mode.is_numeric_char(char) {
    True -> Numeric
    False ->
      case mode.is_alphanumeric_char(char) {
        True -> Alphanumeric
        False ->
          case mode.is_kanji_char(char) {
            True -> Kanji
            False -> Byte
          }
      }
  }
}

fn refine_mode(current: Mode, next: Mode) -> Mode {
  case current, next {
    Byte, _ -> Byte
    _, Byte -> Byte
    Kanji, _ -> Byte
    _, Kanji -> Byte
    Alphanumeric, Numeric -> Alphanumeric
    Numeric, Alphanumeric -> Alphanumeric
    _, _ -> next
  }
}

fn clamp_version_index(requested: Int) -> Int {
  case requested < 1 {
    True -> 0
    False ->
      case requested > total_versions {
        True -> total_versions - 1
        False -> requested - 1
      }
  }
}

fn find_version(
  text: String,
  selected_mode: Mode,
  ecc: ErrorCorrection,
  candidate: Int,
) -> Result(Int, EncodeError) {
  case candidate >= total_versions {
    True -> Error(DataExceedsCapacity(0, 0))
    False -> {
      let count_bits = lookup_cci(selected_mode, candidate)
      let data_bits =
        3 + count_bits + mode.data_bits_length(text, selected_mode)
      let capacity = data_capacity_bits(candidate, ecc)
      case data_bits <= capacity {
        True -> Ok(candidate)
        False -> find_version(text, selected_mode, ecc, candidate + 1)
      }
    }
  }
}

fn data_capacity_bits(index: Int, ecc: ErrorCorrection) -> Int {
  data_codewords(index, ecc) * 8
}

fn data_codewords(index: Int, ecc: ErrorCorrection) -> Int {
  case ecc {
    High -> lookup_int(data_codewords_h, index)
    _ -> lookup_int(data_codewords_m, index)
  }
}

fn lookup_cci(selected_mode: Mode, index: Int) -> Int {
  case selected_mode {
    Numeric -> lookup_int(numeric_cci, index)
    Alphanumeric -> lookup_int(alphanum_cci, index)
    Byte -> lookup_int(byte_cci, index)
    Kanji -> lookup_int(kanji_cci, index)
  }
}

fn lookup_int(table: List(Int), index: Int) -> Int {
  util.at_or(table, index, default: 0)
}

fn mode_indicator(selected_mode: Mode) -> Int {
  case selected_mode {
    Numeric -> 0b001
    Alphanumeric -> 0b010
    Byte -> 0b011
    Kanji -> 0b100
  }
}

fn create_codewords(
  text: String,
  selected_mode: Mode,
  ecc: ErrorCorrection,
  index: Int,
) -> Result(List(Int), EncodeError) {
  let count_bits = lookup_cci(selected_mode, index)
  let count_value = mode.character_count(text, selected_mode)
  use payload <- result_try(mode.encode(text, selected_mode, at_index: 0))
  let capacity = data_capacity_bits(index, ecc)
  let stream =
    bitstream.new()
    |> bitstream.append_bits(mode_indicator(selected_mode), size: 3)
    |> bitstream.append_bits(count_value, size: count_bits)
    |> bitstream.append_bytes(payload)
    |> append_terminator(capacity)
  case bitstream.length_bits(stream) > capacity {
    True -> Error(DataExceedsCapacity(bitstream.length_bits(stream), capacity))
    False -> {
      let aligned = bitstream.pad_to_byte_boundary(stream)
      let padded = pad_to_data(aligned, data_codewords(index, ecc))
      let data_bytes = bitstream.to_byte_list(padded)
      let total = lookup_int(total_codewords_table, index)
      let ec_count = total - data_codewords(index, ecc)
      let ec_bytes = reed_solomon.encode(data_bytes, ec_count)
      Ok(list.append(data_bytes, ec_bytes))
    }
  }
}

fn append_terminator(
  stream: bitstream.BitStream,
  capacity: Int,
) -> bitstream.BitStream {
  let remaining = capacity - bitstream.length_bits(stream)
  let bits = case remaining < 3 {
    True -> remaining
    False -> 3
  }
  case bits <= 0 {
    True -> stream
    False -> bitstream.append_bits(stream, 0, size: bits)
  }
}

fn pad_to_data(
  stream: bitstream.BitStream,
  data_bytes: Int,
) -> bitstream.BitStream {
  do_pad_to_data(stream, data_bytes, 0)
}

fn do_pad_to_data(
  stream: bitstream.BitStream,
  data_bytes: Int,
  index: Int,
) -> bitstream.BitStream {
  let current = list.length(bitstream.to_byte_list(stream))
  case current >= data_bytes {
    True -> stream
    False -> {
      let byte = case index % 2 == 0 {
        True -> 0xEC
        False -> 0x11
      }
      do_pad_to_data(bitstream.append_byte(stream, byte), data_bytes, index + 1)
    }
  }
}

fn build_matrix(
  index: Int,
  ecc: ErrorCorrection,
  h_size: Int,
  v_size: Int,
  total_codewords: Int,
  codewords: List(Int),
) -> matrix.Matrix {
  let base =
    matrix.new(h_size, v_size)
    |> draw_timing_borders(h_size, v_size)
    |> draw_top_left_finder
    |> draw_bottom_right_subfinder(h_size, v_size)
    |> draw_top_right_corner(h_size)
    |> draw_bottom_left_corner(v_size)
    |> draw_separator(h_size, v_size)
    |> draw_alignment_patterns(h_size, v_size)
    |> reserve_format_info(h_size, v_size)
  let placed = place_data(base, h_size, v_size, total_codewords, codewords)
  let masked = apply_fixed_mask(placed)
  place_format_info(masked, index, ecc, h_size, v_size)
}

fn draw_timing_borders(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let top_bottom =
    util.range(0, h_size - 1)
    |> list.fold(target, fn(acc, col) {
      let dark = col % 2 == 0
      acc
      |> matrix.set(0, col, dark, reserved: True)
      |> matrix.set(v_size - 1, col, dark, reserved: True)
    })
  util.range(0, v_size - 1)
  |> list.fold(top_bottom, fn(acc, row) {
    let dark = row % 2 == 0
    acc
    |> matrix.set(row, 0, dark, reserved: True)
    |> matrix.set(row, h_size - 1, dark, reserved: True)
  })
}

fn draw_top_left_finder(target: matrix.Matrix) -> matrix.Matrix {
  util.range(0, 6)
  |> list.fold(target, fn(acc, row) {
    util.range(0, 6)
    |> list.fold(acc, fn(acc2, col) {
      let dark =
        row == 0
        || row == 6
        || col == 0
        || col == 6
        || { row >= 2 && row <= 4 && col >= 2 && col <= 4 }
      matrix.set(acc2, row, col, dark, reserved: True)
    })
  })
}

fn draw_bottom_right_subfinder(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  util.range(0, 4)
  |> list.fold(target, fn(acc, row) {
    util.range(0, 4)
    |> list.fold(acc, fn(acc2, col) {
      let dark =
        row == 0 || row == 4 || col == 0 || col == 4 || { row == 2 && col == 2 }
      matrix.set(acc2, v_size - 5 + row, h_size - 5 + col, dark, reserved: True)
    })
  })
}

fn draw_top_right_corner(target: matrix.Matrix, h_size: Int) -> matrix.Matrix {
  target
  |> matrix.set(0, h_size - 2, True, reserved: True)
  |> matrix.set(1, h_size - 2, False, reserved: True)
  |> matrix.set(1, h_size - 1, True, reserved: True)
}

fn draw_bottom_left_corner(target: matrix.Matrix, v_size: Int) -> matrix.Matrix {
  target
  |> matrix.set(v_size - 2, 0, True, reserved: True)
  |> matrix.set(v_size - 2, 1, False, reserved: True)
  |> matrix.set(v_size - 1, 1, True, reserved: True)
}

fn draw_separator(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let with_right =
    util.range(0, 6)
    |> list.fold(target, fn(acc, row) {
      matrix.set(acc, row, 7, False, reserved: True)
    })
  case v_size > 7 {
    False -> with_right
    True ->
      util.range(0, 7)
      |> list.fold(with_right, fn(acc, col) {
        case col >= h_size {
          True -> acc
          False -> matrix.set(acc, 7, col, False, reserved: True)
        }
      })
  }
}

fn draw_alignment_patterns(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  case h_size > 27 {
    False -> target
    True ->
      case alignment_row_for_width(h_size) {
        Error(_) -> target
        Ok(h_version) ->
          do_draw_alignment_columns(target, h_size, v_size, h_version, 0)
      }
  }
}

fn alignment_row_for_width(h_size: Int) -> Result(Int, Nil) {
  case h_size {
    43 -> Ok(0)
    59 -> Ok(1)
    77 -> Ok(2)
    99 -> Ok(3)
    139 -> Ok(4)
    _ -> Error(Nil)
  }
}

fn do_draw_alignment_columns(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
  h_version: Int,
  index: Int,
) -> matrix.Matrix {
  case index >= 4 {
    True -> target
    False -> {
      let column = lookup_int(alignment_columns, h_version * 4 + index)
      case column {
        0 -> target
        _ ->
          do_draw_alignment_columns(
            draw_alignment_column(target, column, h_size, v_size),
            h_size,
            v_size,
            h_version,
            index + 1,
          )
      }
    }
  }
}

fn draw_alignment_column(
  target: matrix.Matrix,
  column: Int,
  _h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let with_line =
    util.range(0, v_size - 1)
    |> list.fold(target, fn(acc, row) {
      let dark = row % 2 == 0
      matrix.set(acc, row, column, dark, reserved: True)
    })
  with_line
  |> matrix.set(1, column - 1, True, reserved: True)
  |> matrix.set(2, column - 1, True, reserved: True)
  |> matrix.set(1, column + 1, True, reserved: True)
  |> matrix.set(2, column + 1, True, reserved: True)
  |> matrix.set(v_size - 3, column - 1, True, reserved: True)
  |> matrix.set(v_size - 2, column - 1, True, reserved: True)
  |> matrix.set(v_size - 3, column + 1, True, reserved: True)
  |> matrix.set(v_size - 2, column + 1, True, reserved: True)
}

fn reserve_format_info(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let left_main =
    util.range(0, 4)
    |> list.fold(target, fn(acc_i, i) {
      util.range(0, 2)
      |> list.fold(acc_i, fn(acc_j, j) {
        matrix.set(acc_j, i + 1, j + 8, False, reserved: True)
      })
    })
  let left_extra =
    util.range(1, 3)
    |> list.fold(left_main, fn(acc, row) {
      matrix.set(acc, row, 11, False, reserved: True)
    })
  let right_main =
    util.range(0, 4)
    |> list.fold(left_extra, fn(acc_i, i) {
      util.range(0, 2)
      |> list.fold(acc_i, fn(acc_j, j) {
        matrix.set(acc_j, v_size - 6 + i, h_size - 8 + j, False, reserved: True)
      })
    })
  util.range(0, 2)
  |> list.fold(right_main, fn(acc, k) {
    matrix.set(acc, v_size - 6, h_size - 5 + k, False, reserved: True)
  })
}

fn place_data(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
  total_codewords: Int,
  codewords: List(Int),
) -> matrix.Matrix {
  let bits = codewords_to_bits(codewords, [])
  let positions = data_positions(target, h_size, v_size, total_codewords)
  write_bits(target, positions, bits)
}

fn codewords_to_bits(codewords: List(Int), acc: List(Bool)) -> List(Bool) {
  case codewords {
    [] -> list.reverse(acc)
    [byte, ..rest] ->
      codewords_to_bits(rest, [
        bit_at(byte, 0),
        bit_at(byte, 1),
        bit_at(byte, 2),
        bit_at(byte, 3),
        bit_at(byte, 4),
        bit_at(byte, 5),
        bit_at(byte, 6),
        bit_at(byte, 7),
        ..acc
      ])
  }
}

fn bit_at(byte: Int, position: Int) -> Bool {
  byte / power_of_two(position) % 2 == 1
}

fn power_of_two(index: Int) -> Int {
  case index <= 0 {
    True -> 1
    False -> 2 * power_of_two(index - 1)
  }
}

fn data_positions(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
  total_codewords: Int,
) -> List(#(Int, Int)) {
  let bits_needed = total_codewords * 8
  let initial_x = h_size - 3
  do_data_positions(target, initial_x, v_size - 1, 1, 0, bits_needed, [])
}

fn do_data_positions(
  target: matrix.Matrix,
  x: Int,
  y: Int,
  direction: Int,
  collected: Int,
  needed: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case collected >= needed || x < 0 {
    True -> list.reverse(acc)
    False -> {
      let #(acc1, count1) = try_place(target, y, x + 1, acc, collected)
      let #(acc2, count2) = try_place(target, y, x, acc1, count1)
      let #(next_x, next_y, next_dir) =
        advance(matrix.height(target), x, y, direction)
      do_data_positions(target, next_x, next_y, next_dir, count2, needed, acc2)
    }
  }
}

fn try_place(
  target: matrix.Matrix,
  row: Int,
  col: Int,
  acc: List(#(Int, Int)),
  collected: Int,
) -> #(List(#(Int, Int)), Int) {
  case col < 0 || col >= matrix.width(target) {
    True -> #(acc, collected)
    False ->
      case matrix.is_reserved(target, row, col) {
        True -> #(acc, collected)
        False -> #([#(row, col), ..acc], collected + 1)
      }
  }
}

fn advance(v_size: Int, x: Int, y: Int, direction: Int) -> #(Int, Int, Int) {
  case direction {
    1 ->
      case y == 0 {
        True -> #(x - 2, 0, 0)
        False -> #(x, y - 1, 1)
      }
    _ ->
      case y == v_size - 1 {
        True -> #(x - 2, v_size - 1, 1)
        False -> #(x, y + 1, 0)
      }
  }
}

fn write_bits(
  target: matrix.Matrix,
  positions: List(#(Int, Int)),
  bits: List(Bool),
) -> matrix.Matrix {
  case positions, bits {
    [#(row, col), ..rest_positions], [bit, ..rest_bits] ->
      write_bits(
        matrix.set(target, row, col, bit, reserved: False),
        rest_positions,
        rest_bits,
      )
    _, _ -> target
  }
}

fn apply_fixed_mask(target: matrix.Matrix) -> matrix.Matrix {
  do_apply_mask(target, 0, 0)
}

fn do_apply_mask(target: matrix.Matrix, row: Int, col: Int) -> matrix.Matrix {
  case row >= matrix.height(target) {
    True -> target
    False ->
      case col >= matrix.width(target) {
        True -> do_apply_mask(target, row + 1, 0)
        False ->
          case matrix.is_reserved(target, row, col) {
            True -> do_apply_mask(target, row, col + 1)
            False ->
              do_apply_mask(
                matrix.xor(target, row, col, { row / 2 + col / 3 } % 2 == 0),
                row,
                col + 1,
              )
          }
      }
  }
}

fn place_format_info(
  target: matrix.Matrix,
  index: Int,
  ecc: ErrorCorrection,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let table_index = case ecc {
    High -> index + 32
    _ -> index
  }
  let left = lookup_int(format_info_left, table_index)
  let right = lookup_int(format_info_right, table_index)
  let with_left = place_left_format(target, left)
  place_right_format(with_left, right, h_size, v_size)
}

fn place_left_format(target: matrix.Matrix, bits: Int) -> matrix.Matrix {
  let main =
    util.range(0, 4)
    |> list.fold(target, fn(acc_i, i) {
      util.range(0, 2)
      |> list.fold(acc_i, fn(acc_j, j) {
        let dark = bit_at(bits, j * 5 + i)
        matrix.set(acc_j, i + 1, j + 8, dark, reserved: True)
      })
    })
  main
  |> matrix.set(1, 11, bit_at(bits, 15), reserved: True)
  |> matrix.set(2, 11, bit_at(bits, 16), reserved: True)
  |> matrix.set(3, 11, bit_at(bits, 17), reserved: True)
}

fn place_right_format(
  target: matrix.Matrix,
  bits: Int,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let main =
    util.range(0, 4)
    |> list.fold(target, fn(acc_i, i) {
      util.range(0, 2)
      |> list.fold(acc_i, fn(acc_j, j) {
        let dark = bit_at(bits, j * 5 + i)
        matrix.set(acc_j, v_size - 6 + i, h_size - 8 + j, dark, reserved: True)
      })
    })
  main
  |> matrix.set(v_size - 6, h_size - 5, bit_at(bits, 15), reserved: True)
  |> matrix.set(v_size - 6, h_size - 4, bit_at(bits, 16), reserved: True)
  |> matrix.set(v_size - 6, h_size - 3, bit_at(bits, 17), reserved: True)
}

fn result_try(
  result: Result(a, EncodeError),
  callback: fn(a) -> Result(b, EncodeError),
) -> Result(b, EncodeError) {
  case result {
    Ok(value) -> callback(value)
    Error(error) -> Error(error)
  }
}
