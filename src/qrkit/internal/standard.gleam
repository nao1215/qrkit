//// Standard QR Code encoder.

import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import qrkit/error.{type EncodeError, DataExceedsCapacity}
import qrkit/internal/bitstream
import qrkit/internal/format_info
import qrkit/internal/mask
import qrkit/internal/matrix
import qrkit/internal/reed_solomon
import qrkit/internal/segment
import qrkit/internal/util
import qrkit/internal/version
import qrkit/types.{type ErrorCorrection, type ModePreference}

pub opaque type Encoded {
  Encoded(
    version: Int,
    width: Int,
    height: Int,
    mask: Int,
    rows: List(List(Bool)),
  )
}

/// Encode `text` as a Standard QR code.
///
/// `min_version` is `Some(N)` when the caller explicitly pinned the version
/// via `qrkit.with_exact_version(N)` (or the legacy `with_min_version(N)`
/// alias); in that case the encoder uses N as a
/// strict version (a capacity overflow at N returns `Error` instead of
/// promoting to a larger version). When `min_version` is `None`, the
/// encoder picks the smallest version in 1..40 that fits the payload.
pub fn encode(
  text: String,
  ecc: ErrorCorrection,
  min_version: Option(Int),
  eci: Option(Int),
  preference: ModePreference,
) -> Result(Encoded, EncodeError) {
  let #(lo, hi) = case min_version {
    None -> #(1, 40)
    Some(n) -> #(n, n)
  }
  encode_prefixed(text, ecc, lo, hi, eci, preference, <<>>)
}

/// Encode while constraining the version range and prepending arbitrary header
/// bits. Used by structured append to inject the 20-bit SA header.
pub fn encode_prefixed(
  text: String,
  ecc: ErrorCorrection,
  min_version: Int,
  max_version: Int,
  eci: Option(Int),
  preference: ModePreference,
  prefix_bits: BitArray,
) -> Result(Encoded, EncodeError) {
  let prefix_length = bit_array.bit_size(prefix_bits)
  case
    choose_version(
      text,
      ecc,
      version_ranges(min_version, max_version),
      eci,
      preference,
      prefix_length,
      None,
    )
  {
    Error(error) -> Error(error)
    Ok(#(chosen_version, segments)) ->
      case
        create_codewords_prefixed(
          chosen_version,
          ecc,
          segments,
          eci,
          prefix_bits,
        )
      {
        Error(error) -> Error(error)
        Ok(codewords) ->
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
  }
}

/// The character count indicator widens at versions 10 and 27, which changes
/// both the cost of every segment header and which segmentation is shortest.
/// Split `min_version..max_version` at those boundaries so each range is
/// segmented and measured with the indicator widths it will be encoded with.
fn version_ranges(min_version: Int, max_version: Int) -> List(#(Int, Int)) {
  [#(1, 9), #(10, 26), #(27, 40)]
  |> list.filter_map(fn(range) {
    let lo = int.max(range.0, min_version)
    let hi = int.min(range.1, max_version)
    case lo <= hi {
      True -> Ok(#(lo, hi))
      False -> Error(Nil)
    }
  })
}

/// Pick the smallest version in `ranges` that holds the payload, together
/// with the segmentation measured for that version's range.
fn choose_version(
  text: String,
  ecc: ErrorCorrection,
  ranges: List(#(Int, Int)),
  eci: Option(Int),
  preference: ModePreference,
  prefix_length: Int,
  last_error: Option(EncodeError),
) -> Result(#(Int, List(segment.Segment)), EncodeError) {
  case ranges, last_error {
    [], Some(error) -> Error(error)
    [], None -> Error(DataExceedsCapacity(prefix_length, 0))
    [#(lo, hi), ..rest], _ ->
      case segment.optimise(text, lo, preference) {
        Error(error) -> Error(error)
        Ok(segments) -> {
          let bits_needed =
            prefix_length + segment.encoded_bits(segments, lo, eci)
          case best_version_in_range(bits_needed, ecc, lo, hi) {
            Ok(chosen) -> Ok(#(chosen, segments))
            Error(error) ->
              choose_version(
                text,
                ecc,
                rest,
                eci,
                preference,
                prefix_length,
                Some(error),
              )
          }
        }
      }
  }
}

fn best_version_in_range(
  bits_needed: Int,
  ecc: ErrorCorrection,
  min_version: Int,
  max_version: Int,
) -> Result(Int, EncodeError) {
  case
    version.best_version_for_bits(bits_needed, ecc, min_version),
    version.data_capacity_bits(max_version, ecc)
  {
    Ok(chosen), Ok(max_bits) ->
      case chosen > max_version {
        True -> Error(DataExceedsCapacity(bits_needed, max_bits))
        False -> Ok(chosen)
      }
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
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

pub fn mask(encoded: Encoded) -> Int {
  let Encoded(_, _, _, mask, _) = encoded
  mask
}

fn create_codewords_prefixed(
  chosen_version: Int,
  ecc: ErrorCorrection,
  segments: List(segment.Segment),
  eci: Option(Int),
  prefix_bits: BitArray,
) -> Result(List(Int), EncodeError) {
  case version.data_capacity_bits(chosen_version, ecc) {
    Error(error) -> Error(error)
    Ok(capacity_bits) -> {
      let prefixed_stream =
        bitstream.new() |> bitstream.append_bytes(prefix_bits)
      case
        segment.append_to_stream(prefixed_stream, segments, chosen_version, eci)
      {
        Error(error) -> Error(error)
        Ok(stream) ->
          case bitstream.length_bits(stream) > capacity_bits {
            True ->
              Error(DataExceedsCapacity(
                bitstream.length_bits(stream),
                capacity_bits,
              ))
            False ->
              case
                finish_data_stream(stream, chosen_version, ecc, capacity_bits)
              {
                Error(error) -> Error(error)
                Ok(bytes) -> interleave_blocks(bytes, chosen_version, ecc)
              }
          }
      }
    }
  }
}

fn finish_data_stream(
  stream: bitstream.BitStream,
  chosen_version: Int,
  ecc: ErrorCorrection,
  capacity_bits: Int,
) -> Result(List(Int), EncodeError) {
  let terminated = add_terminator(stream, capacity_bits)
  let padded = bitstream.pad_to_byte_boundary(terminated)
  case version.data_codewords(chosen_version, ecc) {
    Error(error) -> Error(error)
    Ok(data_codewords) ->
      Ok(add_pad_bytes(padded, data_codewords) |> bitstream.to_byte_list)
  }
}

fn add_terminator(
  stream: bitstream.BitStream,
  capacity_bits: Int,
) -> bitstream.BitStream {
  let remaining = capacity_bits - bitstream.length_bits(stream)
  let terminator_bits = case remaining >= 4 {
    True -> 4
    False -> remaining
  }
  bitstream.append_bits(stream, 0, size: terminator_bits)
}

fn add_pad_bytes(
  stream: bitstream.BitStream,
  data_codewords: Int,
) -> bitstream.BitStream {
  do_add_pad_bytes(
    stream,
    data_codewords - list.length(bitstream.to_byte_list(stream)),
    0,
  )
}

fn do_add_pad_bytes(
  stream: bitstream.BitStream,
  remaining: Int,
  index: Int,
) -> bitstream.BitStream {
  use <- bool.guard(when: remaining <= 0, return: stream)
  let byte = case index % 2 == 0 {
    True -> 0xEC
    False -> 0x11
  }
  do_add_pad_bytes(
    bitstream.append_byte(stream, byte),
    remaining - 1,
    index + 1,
  )
}

fn interleave_blocks(
  bytes: List(Int),
  chosen_version: Int,
  ecc: ErrorCorrection,
) -> Result(List(Int), EncodeError) {
  case
    version.total_codewords(chosen_version),
    version.ec_blocks(chosen_version, ecc)
  {
    Ok(total_codewords), Ok(ec_total_blocks) ->
      Ok(reed_solomon.encode_interleaved(
        bytes,
        total_codewords: total_codewords,
        blocks: ec_total_blocks,
      ))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

fn build_matrix(
  chosen_version: Int,
  ecc: ErrorCorrection,
  codewords: List(Int),
) -> Result(#(Int, matrix.Matrix), EncodeError) {
  case version.symbol_size(chosen_version) {
    Error(error) -> Error(error)
    Ok(size) -> {
      let placed =
        setup_data(function_patterns(chosen_version, size), codewords)
      let #(best_mask, masked) = choose_best_mask(placed, ecc)
      Ok(#(best_mask, setup_format_info(masked, ecc, best_mask)))
    }
  }
}

/// The matrix with every function pattern drawn and marked reserved: finder,
/// timing and alignment patterns, the format information area (drawn for an
/// arbitrary level and mask; it is rewritten once the mask is chosen), and
/// the version information from version 7.
fn function_patterns(chosen_version: Int, size: Int) -> matrix.Matrix {
  let base =
    matrix.new(size, size)
    |> setup_finder_patterns(chosen_version)
    |> setup_timing_pattern
    |> setup_alignment_patterns(chosen_version)
    |> setup_format_info(types.Medium, 0)
  case chosen_version >= 7 {
    True -> setup_version_info(base, chosen_version)
    False -> base
  }
}

/// The `(row, col)` of every data module of `chosen_version`, in the order
/// codeword bits are placed (and read back by a decoder).
pub fn data_module_positions(chosen_version: Int) -> List(#(Int, Int)) {
  case version.symbol_size(chosen_version) {
    Ok(size) ->
      data_positions(
        function_patterns(chosen_version, size),
        size - 1,
        size - 1,
        -1,
        [],
      )
    Error(_) -> []
  }
}

/// The two 15-bit copies of the format information of a symbol given as
/// `module(row, col)`, each read in the bit order `setup_format_info` writes.
pub fn read_format_copies(
  module: fn(Int, Int) -> Bool,
  size: Int,
) -> #(Int, Int) {
  util.range(0, 14)
  |> list.fold(#(0, 0), fn(acc, index) {
    let vertical_row = case index < 6 {
      True -> index
      False ->
        case index < 8 {
          True -> index + 1
          False -> size - 15 + index
        }
    }
    let horizontal_col = case index < 8 {
      True -> size - index - 1
      False ->
        case index < 9 {
          True -> 15 - index
          False -> 14 - index
        }
    }
    let weight = power_of_two(index)
    #(
      acc.0 + bool_value(module(vertical_row, 8)) * weight,
      acc.1 + bool_value(module(8, horizontal_col)) * weight,
    )
  })
}

fn bool_value(value: Bool) -> Int {
  case value {
    True -> 1
    False -> 0
  }
}

fn choose_best_mask(
  target: matrix.Matrix,
  ecc: ErrorCorrection,
) -> #(Int, matrix.Matrix) {
  choose_best_mask_loop(target, ecc, 0, #(0, target), 0)
}

fn choose_best_mask_loop(
  target: matrix.Matrix,
  ecc: ErrorCorrection,
  candidate: Int,
  best: #(Int, matrix.Matrix),
  best_penalty: Int,
) -> #(Int, matrix.Matrix) {
  case candidate > 7 {
    True -> best
    False -> {
      let masked =
        mask.apply(candidate, to: target)
        |> setup_format_info(ecc, candidate)
      let penalty = mask.penalty_total(masked)
      case candidate == 0 || penalty < best_penalty {
        True ->
          choose_best_mask_loop(
            target,
            ecc,
            candidate + 1,
            #(candidate, masked),
            penalty,
          )
        False ->
          choose_best_mask_loop(target, ecc, candidate + 1, best, best_penalty)
      }
    }
  }
}

fn setup_finder_patterns(
  target: matrix.Matrix,
  _chosen_version: Int,
) -> matrix.Matrix {
  let size = matrix.width(target)
  let positions = [#(0, 0), #(0, size - 7), #(size - 7, 0)]
  list.fold(positions, target, fn(acc, position) {
    let #(row, col) = position
    draw_finder_pattern(acc, row, col)
  })
}

fn draw_finder_pattern(
  target: matrix.Matrix,
  top: Int,
  left: Int,
) -> matrix.Matrix {
  util.range(-1, 7)
  |> list.fold(target, fn(acc, row_offset) {
    util.range(-1, 7)
    |> list.fold(acc, fn(acc2, col_offset) {
      let row = top + row_offset
      let col = left + col_offset
      case inside(acc2, row, col) {
        False -> acc2
        True -> {
          let dark =
            row_offset >= 0
            && row_offset <= 6
            && col_offset >= 0
            && col_offset <= 6
            && {
              row_offset == 0
              || row_offset == 6
              || col_offset == 0
              || col_offset == 6
              || {
                row_offset >= 2
                && row_offset <= 4
                && col_offset >= 2
                && col_offset <= 4
              }
            }
          matrix.set(acc2, row, col, dark, reserved: True)
        }
      }
    })
  })
}

fn setup_timing_pattern(target: matrix.Matrix) -> matrix.Matrix {
  util.range(8, matrix.width(target) - 9)
  |> list.fold(target, fn(acc, index) {
    let dark = index % 2 == 0
    acc
    |> matrix.set(index, 6, dark, reserved: True)
    |> matrix.set(6, index, dark, reserved: True)
  })
}

fn setup_alignment_patterns(
  target: matrix.Matrix,
  chosen_version: Int,
) -> matrix.Matrix {
  alignment_positions(chosen_version)
  |> list.fold(target, fn(acc, position) {
    let #(row, col) = position
    draw_alignment_pattern(acc, row, col)
  })
}

fn draw_alignment_pattern(
  target: matrix.Matrix,
  row: Int,
  col: Int,
) -> matrix.Matrix {
  util.range(-2, 2)
  |> list.fold(target, fn(acc, row_offset) {
    util.range(-2, 2)
    |> list.fold(acc, fn(acc2, col_offset) {
      let dark =
        row_offset == -2
        || row_offset == 2
        || col_offset == -2
        || col_offset == 2
        || { row_offset == 0 && col_offset == 0 }
      matrix.set(acc2, row + row_offset, col + col_offset, dark, reserved: True)
    })
  })
}

fn setup_version_info(
  target: matrix.Matrix,
  chosen_version: Int,
) -> matrix.Matrix {
  let bits = format_info.version_bits(chosen_version)
  util.range(0, 17)
  |> list.fold(target, fn(acc, index) {
    let row = index / 3
    let col = index % 3 + matrix.width(acc) - 11
    let dark = bit_at(bits, index)
    acc
    |> matrix.set(row, col, dark, reserved: True)
    |> matrix.set(col, row, dark, reserved: True)
  })
}

fn setup_format_info(
  target: matrix.Matrix,
  ecc: ErrorCorrection,
  current_mask: Int,
) -> matrix.Matrix {
  let size = matrix.width(target)
  let bits = format_info.format_bits(ecc, current_mask)
  let with_info =
    util.range(0, 14)
    |> list.fold(target, fn(acc, index) {
      let dark = bit_at(bits, index)
      let vertical_row = case index < 6 {
        True -> index
        False ->
          case index < 8 {
            True -> index + 1
            False -> size - 15 + index
          }
      }
      let horizontal_col = case index < 8 {
        True -> size - index - 1
        False ->
          case index < 9 {
            True -> 15 - index
            False -> 14 - index
          }
      }
      acc
      |> matrix.set(vertical_row, 8, dark, reserved: True)
      |> matrix.set(8, horizontal_col, dark, reserved: True)
    })
  matrix.set(with_info, size - 8, 8, True, reserved: True)
}

fn setup_data(target: matrix.Matrix, codewords: List(Int)) -> matrix.Matrix {
  let bits = codewords_to_bits(codewords, [])
  let positions =
    data_positions(
      target,
      matrix.width(target) - 1,
      matrix.width(target) - 1,
      -1,
      [],
    )
  place_bits(target, positions, bits)
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

fn data_positions(
  target: matrix.Matrix,
  col: Int,
  row: Int,
  inc: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case col <= 0 {
    True -> list.reverse(acc)
    False -> {
      let actual_col = case col == 6 {
        True -> 5
        False -> col
      }
      let #(next_acc, next_row, next_inc) =
        scan_column_pair(target, actual_col, row, inc, acc)
      data_positions(target, actual_col - 2, next_row, next_inc, next_acc)
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
  let with_right = reserve_if_data(target, row, col, acc)
  let with_both = reserve_if_data(target, row, col - 1, with_right)
  let next_row = row + inc
  case next_row < 0 || next_row >= matrix.height(target) {
    True -> #(with_both, row, 0 - inc)
    False -> scan_column_pair(target, col, next_row, inc, with_both)
  }
}

fn reserve_if_data(
  target: matrix.Matrix,
  row: Int,
  col: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case matrix.is_reserved(target, row, col) {
    True -> acc
    False -> [#(row, col), ..acc]
  }
}

fn place_bits(
  target: matrix.Matrix,
  positions: List(#(Int, Int)),
  bits: List(Bool),
) -> matrix.Matrix {
  case positions, bits {
    [#(row, col), ..rest_positions], [bit, ..rest_bits] ->
      place_bits(
        matrix.set(target, row, col, bit, reserved: False),
        rest_positions,
        rest_bits,
      )
    [#(row, col), ..rest_positions], [] ->
      place_bits(
        matrix.set(target, row, col, False, reserved: False),
        rest_positions,
        [],
      )
    [], _ -> target
  }
}

fn alignment_positions(chosen_version: Int) -> List(#(Int, Int)) {
  case chosen_version == 1 {
    True -> []
    False -> {
      case version.symbol_size(chosen_version) {
        Ok(size) -> {
          let count = chosen_version / 7 + 2
          let step = case size == 145 {
            True -> 26
            False -> ceil_div(size - 13, 2 * count - 2) * 2
          }
          let coords = alignment_row_col_coords(size, count, step, [6])
          expand_alignment_coords(coords, coords, size, [])
        }
        Error(_) -> []
      }
    }
  }
}

fn alignment_row_col_coords(
  size: Int,
  count: Int,
  step: Int,
  acc: List(Int),
) -> List(Int) {
  case list.length(acc) >= count {
    True -> acc
    False -> {
      let value = size - 7 - { list.length(acc) - 1 } * step
      alignment_row_col_coords(size, count, step, list.append(acc, [value]))
    }
  }
}

fn expand_alignment_coords(
  rows: List(Int),
  cols: List(Int),
  size: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case rows {
    [] -> acc
    [row, ..rest] ->
      expand_alignment_coords(
        rest,
        cols,
        size,
        expand_alignment_row(row, cols, size, acc),
      )
  }
}

fn expand_alignment_row(
  row: Int,
  cols: List(Int),
  size: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case cols {
    [] -> acc
    [col, ..rest] ->
      case finder_overlap(row, col, size) {
        True -> expand_alignment_row(row, rest, size, acc)
        False -> expand_alignment_row(row, rest, size, [#(row, col), ..acc])
      }
  }
}

fn finder_overlap(row: Int, col: Int, size: Int) -> Bool {
  let corner = size - 7
  // Skip alignment-pattern centres that coincide with a finder pattern
  // (top-left, top-right, bottom-left).
  { row == 6 && col == 6 }
  || { row == 6 && col == corner }
  || { row == corner && col == 6 }
}

fn ceil_div(numerator: Int, denominator: Int) -> Int {
  { numerator + denominator - 1 } / denominator
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

fn inside(target: matrix.Matrix, row: Int, col: Int) -> Bool {
  row >= 0
  && row < matrix.height(target)
  && col >= 0
  && col < matrix.width(target)
}
