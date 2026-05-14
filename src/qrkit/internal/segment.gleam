//// Segment building for standard QR Code symbols.

import gleam/list
import gleam/option.{type Option, None, Some}
import qrkit/error.{
  type EncodeError, type Mode, type ModePreference, Alphanumeric, Auto, Byte,
  ForceByte, Kanji, Numeric,
}
import qrkit/internal/bitstream
import qrkit/internal/mode
import qrkit/internal/util

pub opaque type Segment {
  Segment(mode: Mode, data: String, count: Int, bits: Int, index: Int)
}

pub fn mode(segment: Segment) -> Mode {
  let Segment(mode, _, _, _, _) = segment
  mode
}

pub fn data(segment: Segment) -> String {
  let Segment(_, data, _, _, _) = segment
  data
}

pub fn count(segment: Segment) -> Int {
  let Segment(_, _, count, _, _) = segment
  count
}

pub fn bits(segment: Segment) -> Int {
  let Segment(_, _, _, bits, _) = segment
  bits
}

pub fn optimise(
  text: String,
  _version: Int,
  preference: ModePreference,
) -> Result(List(Segment), EncodeError) {
  case preference {
    ForceByte -> Ok([build_segment(Byte, text, 0)])
    Auto ->
      Ok(
        util.characters(text)
        |> greedy_segments(0, [], None)
        |> normalise_segments,
      )
  }
}

pub fn encoded_bits(
  segments: List(Segment),
  version: Int,
  eci: Option(Int),
) -> Int {
  let eci_bits = case eci {
    None -> 0
    Some(value) -> 4 + eci_designator_bits(value)
  }
  eci_bits
  + list.fold(segments, 0, fn(acc, segment) {
    acc + 4 + mode.char_count_bits(mode(segment), version) + bits(segment)
  })
}

pub fn append_to_stream(
  stream: bitstream.BitStream,
  segments: List(Segment),
  version: Int,
  eci: Option(Int),
) -> Result(bitstream.BitStream, EncodeError) {
  let with_eci = case eci {
    None -> Ok(stream)
    Some(value) -> append_eci(stream, value)
  }
  case with_eci {
    Error(error) -> Error(error)
    Ok(stream_with_eci) ->
      do_append_segments(stream_with_eci, segments, version)
  }
}

fn greedy_segments(
  chars: List(String),
  index: Int,
  acc: List(Segment),
  current: Option(#(Mode, String, Int)),
) -> List(Segment) {
  case chars {
    [] ->
      case current {
        Some(#(current_mode, current_text, start)) ->
          list.reverse([build_segment(current_mode, current_text, start), ..acc])
        None -> list.reverse(acc)
      }
    [char, ..rest] -> {
      let next_mode = classify_char(char)
      case current {
        Some(#(current_mode, current_text, start)) if current_mode == next_mode ->
          greedy_segments(
            rest,
            index + 1,
            acc,
            Some(#(current_mode, current_text <> char, start)),
          )
        Some(#(current_mode, current_text, start)) ->
          greedy_segments(
            rest,
            index + 1,
            [build_segment(current_mode, current_text, start), ..acc],
            Some(#(next_mode, char, index)),
          )
        None ->
          greedy_segments(rest, index + 1, acc, Some(#(next_mode, char, index)))
      }
    }
  }
}

fn normalise_segments(segments: List(Segment)) -> List(Segment) {
  segments
  |> merge_numeric_with_alphanumeric
  |> merge_adjacent_same_mode
}

fn merge_numeric_with_alphanumeric(segments: List(Segment)) -> List(Segment) {
  case segments {
    [first, second, ..rest] ->
      case promote_pair(first, second) {
        Some(merged) -> merge_numeric_with_alphanumeric([merged, ..rest])
        None -> [first, ..merge_numeric_with_alphanumeric([second, ..rest])]
      }
    _ -> segments
  }
}

fn promote_pair(first: Segment, second: Segment) -> Option(Segment) {
  let first_mode = mode(first)
  let second_mode = mode(second)
  case is_alnum_family(first_mode) && is_alnum_family(second_mode) {
    True ->
      Some(build_segment(
        Alphanumeric,
        data(first) <> data(second),
        segment_index(first),
      ))
    False -> None
  }
}

fn merge_adjacent_same_mode(segments: List(Segment)) -> List(Segment) {
  case segments {
    [first, second, ..rest] ->
      case mode(first) == mode(second) {
        True ->
          merge_adjacent_same_mode([
            build_segment(
              mode(first),
              data(first) <> data(second),
              segment_index(first),
            ),
            ..rest
          ])
        False -> [first, ..merge_adjacent_same_mode([second, ..rest])]
      }
    [first, ..rest] -> [first, ..merge_adjacent_same_mode(rest)]
    [] -> []
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

fn is_alnum_family(value: Mode) -> Bool {
  case value {
    Numeric -> True
    Alphanumeric -> True
    _ -> False
  }
}

fn build_segment(current_mode: Mode, text: String, index: Int) -> Segment {
  Segment(
    current_mode,
    text,
    mode.character_count(text, current_mode),
    mode.data_bits_length(text, current_mode),
    index,
  )
}

fn do_append_segments(
  stream: bitstream.BitStream,
  segments: List(Segment),
  version: Int,
) -> Result(bitstream.BitStream, EncodeError) {
  case segments {
    [] -> Ok(stream)
    [segment, ..rest] ->
      case
        mode.encode(
          data(segment),
          mode(segment),
          at_index: segment_index(segment),
        )
      {
        Ok(bits) ->
          do_append_segments(
            bitstream.append_bits(
              stream,
              mode.mode_bits(mode(segment)),
              size: 4,
            )
              |> bitstream.append_bits(
                count(segment),
                size: mode.char_count_bits(mode(segment), version),
              )
              |> bitstream.append_bytes(bits),
            rest,
            version,
          )
        Error(error) -> Error(error)
      }
  }
}

fn append_eci(
  stream: bitstream.BitStream,
  designator: Int,
) -> Result(bitstream.BitStream, EncodeError) {
  case designator < 0 {
    True -> Ok(stream)
    False ->
      case designator < 128 {
        True ->
          Ok(
            stream
            |> bitstream.append_bits(0b0111, size: 4)
            |> bitstream.append_bits(designator, size: 8),
          )
        False ->
          case designator < 16_384 {
            True ->
              Ok(
                stream
                |> bitstream.append_bits(0b0111, size: 4)
                |> bitstream.append_bits(0b10, size: 2)
                |> bitstream.append_bits(designator, size: 14),
              )
            False ->
              Ok(
                stream
                |> bitstream.append_bits(0b0111, size: 4)
                |> bitstream.append_bits(0b110, size: 3)
                |> bitstream.append_bits(designator, size: 21),
              )
          }
      }
  }
}

fn eci_designator_bits(value: Int) -> Int {
  case value < 128 {
    True -> 8
    False ->
      case value < 16_384 {
        True -> 16
        False -> 24
      }
  }
}

fn segment_index(segment: Segment) -> Int {
  let Segment(_, _, _, _, index) = segment
  index
}
