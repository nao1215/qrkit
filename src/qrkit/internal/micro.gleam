//// Micro QR Code encoder (ISO/IEC 18004 §6 + Annex K).
////
//// Supports M1 (11×11) through M4 (17×17). Reuses the standard QR Reed-Solomon
//// engine, bitstream, and matrix primitives; mask selection, format info and
//// data placement follow the Micro QR rules.

import gleam/list
import qrkit/error.{
  type EncodeError, type ErrorCorrection, type Mode, type ModePreference,
  Alphanumeric, Byte, DataExceedsCapacity, IncompatibleOptions, InvalidVersion,
  Kanji, Low, Medium, Numeric, Quartile,
}
import qrkit/internal/bitstream
import qrkit/internal/matrix
import qrkit/internal/mode
import qrkit/internal/reed_solomon
import qrkit/internal/util

pub opaque type Encoded {
  Encoded(
    version: Int,
    width: Int,
    height: Int,
    mask: Int,
    rows: List(List(Bool)),
  )
}

pub fn version(encoded: Encoded) -> Int {
  let Encoded(version, _, _, _, _) = encoded
  version
}

pub fn width(encoded: Encoded) -> Int {
  let Encoded(_, width, _, _, _) = encoded
  width
}

pub fn height(encoded: Encoded) -> Int {
  let Encoded(_, _, height, _, _) = encoded
  height
}

pub fn rows(encoded: Encoded) -> List(List(Bool)) {
  let Encoded(_, _, _, _, rows) = encoded
  rows
}

const finder_size: Int = 7

const min_version: Int = 1

const max_version: Int = 4

const format_xor_mask: Int = 0x4445

const format_info_table: List(Int) = [
  0x4445, 0x4172, 0x4E2B, 0x4B1C, 0x55AE, 0x5099, 0x5FC0, 0x5AF7, 0x6793, 0x62A4,
  0x6DFD, 0x68CA, 0x7678, 0x734F, 0x7C16, 0x7921, 0x06DE, 0x03E9, 0x0CB0, 0x0987,
  0x1735, 0x1202, 0x1D5B, 0x186C, 0x2508, 0x203F, 0x2F66, 0x2A51, 0x34E3, 0x31D4,
  0x3E8D, 0x3BBA,
]

/// Encode `text` into a Micro QR code of the smallest version that fits.
pub fn encode(
  text: String,
  ecc: ErrorCorrection,
  requested_version: Int,
  preference: ModePreference,
) -> Result(Encoded, EncodeError) {
  use _ <- result_try(validate_version(requested_version))
  use _ <- result_try(validate_ecc(ecc))
  use selected_mode <- result_try(select_mode(text, preference))
  use chosen_version <- result_try(find_version(
    text,
    selected_mode,
    ecc,
    requested_version,
  ))
  use codewords <- result_try(create_codewords(
    text,
    selected_mode,
    ecc,
    chosen_version,
  ))
  case build_matrix(chosen_version, ecc, codewords) {
    Ok(#(best_mask, final_matrix)) ->
      Ok(Encoded(
        chosen_version,
        matrix.width(final_matrix),
        matrix.height(final_matrix),
        best_mask,
        matrix.rows(final_matrix),
      ))
    Error(error) -> Error(error)
  }
}

/// Return the side length of a Micro QR version (M1..M4 → 11..17).
pub fn symbol_size(version: Int) -> Result(Int, EncodeError) {
  case version >= min_version && version <= max_version {
    True -> Ok(version * 2 + 9)
    False -> Error(InvalidVersion(version))
  }
}

/// Return the maximum data-and-header bit capacity for `(version, ecc)`.
pub fn data_capacity_bits(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  case version, ecc {
    1, Low -> Ok(20)
    2, Low -> Ok(40)
    2, Medium -> Ok(32)
    3, Low -> Ok(84)
    3, Medium -> Ok(68)
    4, Low -> Ok(128)
    4, Medium -> Ok(112)
    4, Quartile -> Ok(80)
    _, _ ->
      Error(IncompatibleOptions(
        "Micro QR M"
        <> int_to_str(version)
        <> " does not support the requested error correction level",
      ))
  }
}

/// Number of error-correction codewords for `(version, ecc)`.
pub fn ec_codewords(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  case version, ecc {
    1, Low -> Ok(2)
    2, Low -> Ok(5)
    2, Medium -> Ok(6)
    3, Low -> Ok(6)
    3, Medium -> Ok(8)
    4, Low -> Ok(8)
    4, Medium -> Ok(10)
    4, Quartile -> Ok(14)
    _, _ ->
      Error(IncompatibleOptions(
        "Micro QR M"
        <> int_to_str(version)
        <> " does not support the requested error correction level",
      ))
  }
}

fn validate_version(version: Int) -> Result(Nil, EncodeError) {
  case version >= min_version && version <= max_version {
    True -> Ok(Nil)
    False -> Error(InvalidVersion(version))
  }
}

fn validate_ecc(ecc: ErrorCorrection) -> Result(Nil, EncodeError) {
  case ecc {
    Low | Medium | Quartile -> Ok(Nil)
    _ ->
      Error(IncompatibleOptions(
        "Micro QR does not support the High error correction level",
      ))
  }
}

fn select_mode(
  text: String,
  preference: ModePreference,
) -> Result(Mode, EncodeError) {
  case preference {
    error.ForceByte -> Ok(Byte)
    error.Auto -> Ok(detect_uniform_mode(util.characters(text), Numeric))
  }
}

fn detect_uniform_mode(chars: List(String), best: Mode) -> Mode {
  case chars {
    [] -> best
    [char, ..rest] ->
      detect_uniform_mode(rest, refine_mode(best, classify_char(char)))
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

fn find_version(
  text: String,
  selected_mode: Mode,
  ecc: ErrorCorrection,
  requested_version: Int,
) -> Result(Int, EncodeError) {
  do_find_version(text, selected_mode, ecc, requested_version)
}

fn do_find_version(
  text: String,
  selected_mode: Mode,
  ecc: ErrorCorrection,
  candidate: Int,
) -> Result(Int, EncodeError) {
  case candidate > max_version {
    True -> Error(DataExceedsCapacity(0, 0))
    False -> {
      case mode_supported(selected_mode, candidate) {
        False -> do_find_version(text, selected_mode, ecc, candidate + 1)
        True ->
          case data_capacity_bits(candidate, ecc) {
            Error(_) -> do_find_version(text, selected_mode, ecc, candidate + 1)
            Ok(capacity) ->
              case encoded_bits(text, selected_mode, candidate) {
                Error(_) ->
                  do_find_version(text, selected_mode, ecc, candidate + 1)
                Ok(required) ->
                  case required <= capacity {
                    True -> Ok(candidate)
                    False ->
                      do_find_version(text, selected_mode, ecc, candidate + 1)
                  }
              }
          }
      }
    }
  }
}

fn encoded_bits(
  text: String,
  selected_mode: Mode,
  version: Int,
) -> Result(Int, EncodeError) {
  let mode_bits_count = mode_indicator_bits(version)
  case mode_supported(selected_mode, version) {
    False ->
      Error(IncompatibleOptions(
        "Mode not supported by Micro QR M" <> int_to_str(version),
      ))
    True ->
      case char_count_bits_for_mode(selected_mode, version) {
        Error(error) -> Error(error)
        Ok(count_bits) -> {
          let data_bits = mode.data_bits_length(text, selected_mode)
          Ok(mode_bits_count + count_bits + data_bits)
        }
      }
  }
}

fn mode_supported(selected_mode: Mode, version: Int) -> Bool {
  case version, selected_mode {
    1, Numeric -> True
    1, _ -> False
    2, Numeric | 2, Alphanumeric -> True
    2, _ -> False
    _, _ -> True
  }
}

fn mode_indicator_bits(version: Int) -> Int {
  version - 1
}

fn mode_indicator_value(selected_mode: Mode) -> Int {
  case selected_mode {
    Numeric -> 0
    Alphanumeric -> 1
    Byte -> 2
    Kanji -> 3
  }
}

fn char_count_bits_for_mode(
  selected_mode: Mode,
  version: Int,
) -> Result(Int, EncodeError) {
  case version, selected_mode {
    1, Numeric -> Ok(3)
    2, Numeric -> Ok(4)
    2, Alphanumeric -> Ok(3)
    3, Numeric -> Ok(5)
    3, Alphanumeric -> Ok(4)
    3, Byte -> Ok(4)
    3, Kanji -> Ok(3)
    4, Numeric -> Ok(6)
    4, Alphanumeric -> Ok(5)
    4, Byte -> Ok(5)
    4, Kanji -> Ok(4)
    _, _ ->
      Error(IncompatibleOptions(
        "Mode is not supported by Micro QR M" <> int_to_str(version),
      ))
  }
}

fn create_codewords(
  text: String,
  selected_mode: Mode,
  ecc: ErrorCorrection,
  version: Int,
) -> Result(List(Int), EncodeError) {
  use capacity <- result_try(data_capacity_bits(version, ecc))
  use count_bits <- result_try(char_count_bits_for_mode(selected_mode, version))
  let count_value = mode.character_count(text, selected_mode)
  use payload <- result_try(mode.encode(text, selected_mode, at_index: 0))
  let stream =
    bitstream.new()
    |> append_mode_indicator(selected_mode, version)
    |> bitstream.append_bits(count_value, size: count_bits)
    |> bitstream.append_bytes(payload)
  let total_bits = bitstream.length_bits(stream)
  case total_bits > capacity {
    True -> Error(DataExceedsCapacity(total_bits, capacity))
    False -> {
      let terminator_bits = terminator_size(version, capacity - total_bits)
      let with_terminator =
        bitstream.append_bits(stream, 0, size: terminator_bits)
      let padded = pad_to_capacity(with_terminator, version, ecc)
      use data_bytes <- result_try(Ok(bitstream.to_byte_list(padded)))
      use ec_bytes <- result_try(compute_ec(data_bytes, version, ecc))
      Ok(list.append(data_bytes, ec_bytes))
    }
  }
}

fn append_mode_indicator(
  stream: bitstream.BitStream,
  selected_mode: Mode,
  version: Int,
) -> bitstream.BitStream {
  let bits = mode_indicator_bits(version)
  case bits {
    0 -> stream
    _ ->
      bitstream.append_bits(stream, mode_indicator_value(selected_mode), bits)
  }
}

fn terminator_size(version: Int, remaining: Int) -> Int {
  let target = version * 2 + 1
  case remaining < target {
    True -> remaining
    False -> target
  }
}

fn pad_to_capacity(
  stream: bitstream.BitStream,
  version: Int,
  ecc: ErrorCorrection,
) -> bitstream.BitStream {
  let aligned = bitstream.pad_to_byte_boundary(stream)
  let data_bytes_count = case data_codewords(version, ecc) {
    Ok(value) -> value
    Error(_) -> 0
  }
  pad_alternating(aligned, data_bytes_count, 0)
}

fn pad_alternating(
  stream: bitstream.BitStream,
  target_bytes: Int,
  index: Int,
) -> bitstream.BitStream {
  let current_bytes = list.length(bitstream.to_byte_list(stream))
  case current_bytes >= target_bytes {
    True -> stream
    False -> {
      let byte = case index % 2 == 0 {
        True -> 0xEC
        False -> 0x11
      }
      pad_alternating(
        bitstream.append_byte(stream, byte),
        target_bytes,
        index + 1,
      )
    }
  }
}

/// Total number of full data codewords for `(version, ecc)`. Half-byte cases
/// (M1-L, M3-L, M3-M) round up to the next byte; the half-codeword behaviour is
/// applied during matrix placement.
pub fn data_codewords(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  case data_capacity_bits(version, ecc) {
    Ok(bits) -> Ok({ bits + 7 } / 8)
    Error(error) -> Error(error)
  }
}

fn compute_ec(
  data: List(Int),
  version: Int,
  ecc: ErrorCorrection,
) -> Result(List(Int), EncodeError) {
  case ec_codewords(version, ecc) {
    Ok(degree) -> Ok(reed_solomon.encode(data, degree))
    Error(error) -> Error(error)
  }
}

fn has_half_codeword(version: Int, ecc: ErrorCorrection) -> Bool {
  case version, ecc {
    1, Low -> True
    3, Low -> True
    3, Medium -> True
    _, _ -> False
  }
}

fn build_matrix(
  chosen_version: Int,
  ecc: ErrorCorrection,
  codewords: List(Int),
) -> Result(#(Int, matrix.Matrix), EncodeError) {
  case symbol_size(chosen_version) {
    Error(error) -> Error(error)
    Ok(size) -> {
      let base =
        matrix.new(size, size)
        |> draw_finder(size)
        |> draw_timing(size)
        |> reserve_format_info(size)
      let with_data = place_codewords(base, codewords, chosen_version, ecc)
      let #(best_mask, masked) =
        choose_best_mask(with_data, chosen_version, ecc, size)
      Ok(#(best_mask, place_format_info(masked, chosen_version, ecc, best_mask)))
    }
  }
}

fn draw_finder(target: matrix.Matrix, _size: Int) -> matrix.Matrix {
  util.range(0, finder_size)
  |> list.fold(target, fn(acc, row) {
    util.range(0, finder_size)
    |> list.fold(acc, fn(acc2, col) { draw_finder_module(acc2, row, col) })
  })
}

fn draw_finder_module(
  target: matrix.Matrix,
  row: Int,
  col: Int,
) -> matrix.Matrix {
  let dark = case row == finder_size || col == finder_size {
    True -> False
    False ->
      row == 0
      || row == finder_size - 1
      || col == 0
      || col == finder_size - 1
      || { row >= 2 && row <= 4 && col >= 2 && col <= 4 }
  }
  matrix.set(target, row, col, dark, reserved: True)
}

fn draw_timing(target: matrix.Matrix, size: Int) -> matrix.Matrix {
  util.range(finder_size + 1, size - 1)
  |> list.fold(target, fn(acc, index) {
    let dark = index % 2 == 0
    acc
    |> matrix.set(0, index, dark, reserved: True)
    |> matrix.set(index, 0, dark, reserved: True)
  })
}

fn reserve_format_info(target: matrix.Matrix, _size: Int) -> matrix.Matrix {
  let horizontal =
    util.range(1, 8)
    |> list.fold(target, fn(acc, col) {
      matrix.set(acc, 8, col, False, reserved: True)
    })
  util.range(1, 7)
  |> list.fold(horizontal, fn(acc, row) {
    matrix.set(acc, row, 8, False, reserved: True)
  })
}

fn place_codewords(
  target: matrix.Matrix,
  codewords: List(Int),
  version: Int,
  ecc: ErrorCorrection,
) -> matrix.Matrix {
  let half = has_half_codeword(version, ecc)
  let data_count = case data_codewords(version, ecc) {
    Ok(value) -> value
    Error(_) -> 0
  }
  let bits = codewords_to_bits(codewords, data_count, half, 0, [])
  let positions =
    data_positions(target, matrix.width(target) - 1, matrix.height(target) - 1)
  write_bits(target, positions, bits)
}

fn codewords_to_bits(
  codewords: List(Int),
  data_count: Int,
  half_codeword: Bool,
  index: Int,
  acc: List(Bool),
) -> List(Bool) {
  case codewords {
    [] -> list.reverse(acc)
    [byte, ..rest] -> {
      let bit_count = case half_codeword && index + 1 == data_count {
        True -> 4
        False -> 8
      }
      // Write bit_count bits starting from the high end (MSB first) so a half
      // codeword contributes bits 7..4 — ISO/IEC 18004 §6.4.10.
      let next_acc = append_byte_bits(byte, 7, bit_count, acc)
      codewords_to_bits(rest, data_count, half_codeword, index + 1, next_acc)
    }
  }
}

fn append_byte_bits(
  byte: Int,
  bit_position: Int,
  remaining: Int,
  acc: List(Bool),
) -> List(Bool) {
  case remaining <= 0 {
    True -> acc
    False ->
      append_byte_bits(byte, bit_position - 1, remaining - 1, [
        bit_at(byte, bit_position),
        ..acc
      ])
  }
}

fn bit_at(value: Int, index: Int) -> Bool {
  value / power_of_two(index) % 2 == 1
}

fn power_of_two(index: Int) -> Int {
  case index <= 0 {
    True -> 1
    False -> 2 * power_of_two(index - 1)
  }
}

fn data_positions(
  target: matrix.Matrix,
  col: Int,
  row: Int,
) -> List(#(Int, Int)) {
  do_data_positions(target, col, row, -1, [])
}

fn do_data_positions(
  target: matrix.Matrix,
  col: Int,
  row: Int,
  inc: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case col <= 0 {
    True -> list.reverse(acc)
    False -> {
      let #(next_acc, last_row, next_inc) =
        scan_column_pair(target, col, row, inc, acc)
      do_data_positions(target, col - 2, last_row, next_inc, next_acc)
    }
  }
}

fn scan_column_pair(
  target: matrix.Matrix,
  col: Int,
  row: Int,
  inc: Int,
  acc: List(#(Int, Int)),
) -> #(List(#(Int, Int)), Int, Int) {
  let with_right = maybe_take(target, row, col, acc)
  let with_both = maybe_take(target, row, col - 1, with_right)
  let next_row = row + inc
  case next_row < 0 || next_row >= matrix.height(target) {
    True -> #(with_both, row, 0 - inc)
    False -> scan_column_pair(target, col, next_row, inc, with_both)
  }
}

fn maybe_take(
  target: matrix.Matrix,
  row: Int,
  col: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case col < 0 {
    True -> acc
    False ->
      case matrix.is_reserved(target, row, col) {
        True -> acc
        False -> [#(row, col), ..acc]
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

fn choose_best_mask(
  target: matrix.Matrix,
  version: Int,
  ecc: ErrorCorrection,
  size: Int,
) -> #(Int, matrix.Matrix) {
  do_choose_mask(target, version, ecc, size, 0, 0, target, -1)
}

fn do_choose_mask(
  target: matrix.Matrix,
  version: Int,
  ecc: ErrorCorrection,
  size: Int,
  candidate: Int,
  best_mask: Int,
  best_matrix: matrix.Matrix,
  best_score: Int,
) -> #(Int, matrix.Matrix) {
  case candidate > 3 {
    True -> #(best_mask, best_matrix)
    False -> {
      let with_data = apply_mask(target, candidate)
      let placed = place_format_info(with_data, version, ecc, candidate)
      let score = micro_penalty(placed, size)
      case best_score < 0 || score > best_score {
        True ->
          do_choose_mask(
            target,
            version,
            ecc,
            size,
            candidate + 1,
            candidate,
            placed,
            score,
          )
        False ->
          do_choose_mask(
            target,
            version,
            ecc,
            size,
            candidate + 1,
            best_mask,
            best_matrix,
            best_score,
          )
      }
    }
  }
}

fn apply_mask(target: matrix.Matrix, mask: Int) -> matrix.Matrix {
  do_apply_mask(target, mask, 0, 0)
}

fn do_apply_mask(
  target: matrix.Matrix,
  mask: Int,
  row: Int,
  col: Int,
) -> matrix.Matrix {
  case row >= matrix.height(target) {
    True -> target
    False ->
      case col >= matrix.width(target) {
        True -> do_apply_mask(target, mask, row + 1, 0)
        False ->
          case matrix.is_reserved(target, row, col) {
            True -> do_apply_mask(target, mask, row, col + 1)
            False ->
              do_apply_mask(
                matrix.xor(target, row, col, micro_mask_at(mask, row, col)),
                mask,
                row,
                col + 1,
              )
          }
      }
  }
}

fn micro_mask_at(mask: Int, row: Int, col: Int) -> Bool {
  case mask {
    0 -> row % 2 == 0
    1 -> { row / 2 + col / 3 } % 2 == 0
    2 -> { row * col % 2 + row * col % 3 } % 2 == 0
    _ -> { { row + col } % 2 + row * col % 3 } % 2 == 0
  }
}

/// Annex K evaluation: count dark modules on the right column and bottom row
/// of the symbol; pick the mask that maximises the score
/// `min(rp1, rp2) * 16 + max(rp1, rp2)` (ISO/IEC 18004 §G.2 / Annex K).
fn micro_penalty(target: matrix.Matrix, size: Int) -> Int {
  let last = size - 1
  let dark_right = count_dark_edge(target, last, 1, last, True)
  let dark_bottom = count_dark_edge(target, 1, last, last, False)
  let high = case dark_right >= dark_bottom {
    True -> dark_right
    False -> dark_bottom
  }
  let low = case dark_right >= dark_bottom {
    True -> dark_bottom
    False -> dark_right
  }
  low * 16 + high
}

fn count_dark_edge(
  target: matrix.Matrix,
  axis: Int,
  from: Int,
  to: Int,
  vertical: Bool,
) -> Int {
  do_count_dark_edge(target, axis, from, to, vertical, 0)
}

fn do_count_dark_edge(
  target: matrix.Matrix,
  axis: Int,
  current: Int,
  to: Int,
  vertical: Bool,
  acc: Int,
) -> Int {
  case current > to {
    True -> acc
    False -> {
      let dark = case vertical {
        True -> matrix.get(target, current, axis)
        False -> matrix.get(target, axis, current)
      }
      let next_acc = case dark {
        True -> acc + 1
        False -> acc
      }
      do_count_dark_edge(target, axis, current + 1, to, vertical, next_acc)
    }
  }
}

fn place_format_info(
  target: matrix.Matrix,
  version: Int,
  ecc: ErrorCorrection,
  mask: Int,
) -> matrix.Matrix {
  let bits = format_bits(version, ecc, mask)
  let horizontal = place_horizontal_format(target, bits)
  place_vertical_format(horizontal, bits)
}

fn place_horizontal_format(target: matrix.Matrix, bits: Int) -> matrix.Matrix {
  util.range(0, 7)
  |> list.fold(target, fn(acc, index) {
    let col = index + 1
    let dark = bit_at(bits, 14 - index)
    matrix.set(acc, 8, col, dark, reserved: True)
  })
}

fn place_vertical_format(target: matrix.Matrix, bits: Int) -> matrix.Matrix {
  util.range(0, 6)
  |> list.fold(target, fn(acc, index) {
    let row = 7 - index
    let dark = bit_at(bits, 6 - index)
    matrix.set(acc, row, 8, dark, reserved: True)
  })
}

fn format_bits(version: Int, ecc: ErrorCorrection, mask: Int) -> Int {
  case symbol_number(version, ecc) {
    Ok(number) -> {
      let index = number * 4 + mask
      util.at_or(format_info_table, index, default: format_xor_mask)
    }
    Error(_) -> format_xor_mask
  }
}

fn symbol_number(version: Int, ecc: ErrorCorrection) -> Result(Int, EncodeError) {
  case version, ecc {
    1, Low -> Ok(0)
    2, Low -> Ok(1)
    2, Medium -> Ok(2)
    3, Low -> Ok(3)
    3, Medium -> Ok(4)
    4, Low -> Ok(5)
    4, Medium -> Ok(6)
    4, Quartile -> Ok(7)
    _, _ ->
      Error(IncompatibleOptions(
        "Micro QR M"
        <> int_to_str(version)
        <> " does not support the requested error correction level",
      ))
  }
}

fn int_to_str(value: Int) -> String {
  case value {
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    _ -> "?"
  }
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
