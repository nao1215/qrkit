//// Standard QR Code encoder.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import qrkit/internal/bitstream
import qrkit/internal/error.{type EncodeError, DataExceedsCapacity}
import qrkit/internal/format_info
import qrkit/internal/mask
import qrkit/internal/matrix
import qrkit/internal/reed_solomon
import qrkit/internal/segment
import qrkit/internal/types.{type ErrorCorrection, type ModePreference}
import qrkit/internal/util
import qrkit/internal/version

/// Encode `text` as a Standard QR code.
///
/// `exact_version` is `Some(N)` when the caller pinned the version with
/// `EncodeOptions(version: Some(N))`: the symbol is version N, and a payload that
/// does not fit returns an `Error`. When it is `None`, the encoder picks the
/// smallest version in 1..40 that fits the payload.
pub fn encode(
  text: String,
  ecc: ErrorCorrection,
  exact_version: Option(Int),
  eci: Option(Int),
  preference: ModePreference,
) -> Result(matrix.Encoded, EncodeError) {
  let #(lo, hi) = case exact_version {
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
) -> Result(matrix.Encoded, EncodeError) {
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
              Ok(matrix.encoded(
                final_matrix,
                version: chosen_version,
                mask: best_mask,
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
      Ok(
        bitstream.append_pad_codewords(padded, until: data_codewords)
        |> bitstream.to_byte_list,
      )
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
    |> setup_finder_patterns
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
      matrix.data_positions(
        function_patterns(chosen_version, size),
        skip_column: Some(timing_column),
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
  int.range(from: 0, to: 15, with: #(0, 0), run: fn(acc, index) {
    let #(vertical_row, horizontal_col) = format_info_position(index, size)
    let weight = int.bitwise_shift_left(1, index)
    #(
      acc.0 + util.bool_to_int(module(vertical_row, 8)) * weight,
      acc.1 + util.bool_to_int(module(8, horizontal_col)) * weight,
    )
  })
}

/// Where bit `index` (0..14) of the format information goes: the row of the
/// copy in column 8 and the column of the copy in row 8.
fn format_info_position(index: Int, size: Int) -> #(Int, Int) {
  let vertical_row = case index < 6, index < 8 {
    True, _ -> index
    False, True -> index + 1
    False, False -> size - 15 + index
  }
  let horizontal_col = case index < 8, index < 9 {
    True, _ -> size - index - 1
    False, True -> 15 - index
    False, False -> 14 - index
  }
  #(vertical_row, horizontal_col)
}

/// Try the eight masks and keep the one with the lowest penalty; the lowest
/// mask number wins a tie.
fn choose_best_mask(
  target: matrix.Matrix,
  ecc: ErrorCorrection,
) -> #(Int, matrix.Matrix) {
  let evaluate = fn(candidate) {
    let masked =
      mask.apply(candidate, to: target)
      |> setup_format_info(ecc, candidate)
    #(candidate, masked, mask.penalty_total(masked))
  }
  let #(best_mask, best_matrix, _) =
    list.fold([1, 2, 3, 4, 5, 6, 7], evaluate(0), fn(best, candidate) {
      let next = evaluate(candidate)
      case next.2 < best.2 {
        True -> next
        False -> best
      }
    })
  #(best_mask, best_matrix)
}

fn setup_finder_patterns(target: matrix.Matrix) -> matrix.Matrix {
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
  int.range(from: -1, to: 8, with: target, run: fn(acc, row_offset) {
    int.range(from: -1, to: 8, with: acc, run: fn(acc2, col_offset) {
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
  int.range(
    from: 8,
    to: matrix.width(target) - 8,
    with: target,
    run: fn(acc, index) {
      let dark = index % 2 == 0
      acc
      |> matrix.set(index, 6, dark, reserved: True)
      |> matrix.set(6, index, dark, reserved: True)
    },
  )
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
  int.range(from: -2, to: 3, with: target, run: fn(acc, row_offset) {
    int.range(from: -2, to: 3, with: acc, run: fn(acc2, col_offset) {
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
  int.range(from: 0, to: 18, with: target, run: fn(acc, index) {
    let row = index / 3
    let col = index % 3 + matrix.width(acc) - 11
    let dark = util.bit_at(bits, index)
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
    int.range(from: 0, to: 15, with: target, run: fn(acc, index) {
      let dark = util.bit_at(bits, index)
      let #(vertical_row, horizontal_col) = format_info_position(index, size)
      acc
      |> matrix.set(vertical_row, 8, dark, reserved: True)
      |> matrix.set(8, horizontal_col, dark, reserved: True)
    })
  matrix.set(with_info, size - 8, 8, True, reserved: True)
}

fn setup_data(target: matrix.Matrix, codewords: List(Int)) -> matrix.Matrix {
  matrix.write_bits(
    target,
    matrix.data_positions(target, skip_column: Some(timing_column)),
    bitstream.bytes_to_bits(codewords),
  )
}

/// The vertical timing pattern, which data column pairs step over.
const timing_column: Int = 6

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

fn inside(target: matrix.Matrix, row: Int, col: Int) -> Bool {
  row >= 0
  && row < matrix.height(target)
  && col >= 0
  && col < matrix.width(target)
}
