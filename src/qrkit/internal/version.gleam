//// Standard QR Code version and capacity tables.

import qrkit/error.{type EncodeError, DataExceedsCapacity, InvalidVersion}
import qrkit/internal/util
import qrkit/types.{type ErrorCorrection, High, Low, Medium, Quartile}

const total_codewords_table = [
  0, 26, 44, 70, 100, 134, 172, 196, 242, 292, 346, 404, 466, 532, 581, 655, 733,
  815, 901, 991, 1085, 1156, 1258, 1364, 1474, 1588, 1706, 1828, 1921, 2051,
  2185, 2323, 2465, 2611, 2761, 2876, 3034, 3196, 3362, 3532, 3706,
]

const ec_blocks_table = [
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 2, 2, 4, 1, 2, 4, 4, 2, 4, 4, 4, 2, 4,
  6, 5, 2, 4, 6, 6, 2, 5, 8, 8, 4, 5, 8, 8, 4, 5, 8, 11, 4, 8, 10, 11, 4, 9, 12,
  16, 4, 9, 16, 16, 6, 10, 12, 18, 6, 10, 17, 16, 6, 11, 16, 19, 6, 13, 18, 21,
  7, 14, 21, 25, 8, 16, 20, 25, 8, 17, 23, 25, 9, 17, 23, 34, 9, 18, 25, 30, 10,
  20, 27, 32, 12, 21, 29, 35, 12, 23, 34, 37, 12, 25, 34, 40, 13, 26, 35, 42, 14,
  28, 38, 45, 15, 29, 40, 48, 16, 31, 43, 51, 17, 33, 45, 54, 18, 35, 48, 57, 19,
  37, 51, 60, 19, 38, 53, 63, 20, 40, 56, 66, 21, 43, 59, 70, 22, 45, 62, 74, 24,
  47, 65, 77, 25, 49, 68, 81,
]

const ec_codewords_table = [
  7, 10, 13, 17, 10, 16, 22, 28, 15, 26, 36, 44, 20, 36, 52, 64, 26, 48, 72, 88,
  36, 64, 96, 112, 40, 72, 108, 130, 48, 88, 132, 156, 60, 110, 160, 192, 72,
  130, 192, 224, 80, 150, 224, 264, 96, 176, 260, 308, 104, 198, 288, 352, 120,
  216, 320, 384, 132, 240, 360, 432, 144, 280, 408, 480, 168, 308, 448, 532, 180,
  338, 504, 588, 196, 364, 546, 650, 224, 416, 600, 700, 224, 442, 644, 750, 252,
  476, 690, 816, 270, 504, 750, 900, 300, 560, 810, 960, 312, 588, 870, 1050,
  336, 644, 952, 1110, 360, 700, 1020, 1200, 390, 728, 1050, 1260, 420, 784,
  1140, 1350, 450, 812, 1200, 1440, 480, 868, 1290, 1530, 510, 924, 1350, 1620,
  540, 980, 1440, 1710, 570, 1036, 1530, 1800, 570, 1064, 1590, 1890, 600, 1120,
  1680, 1980, 630, 1204, 1770, 2100, 660, 1260, 1860, 2220, 720, 1316, 1950,
  2310, 750, 1372, 2040, 2430,
]

pub fn is_valid(version: Int) -> Bool {
  version >= 1 && version <= 40
}

pub fn symbol_size(version: Int) -> Result(Int, EncodeError) {
  case is_valid(version) {
    True -> Ok(version * 4 + 17)
    False -> Error(InvalidVersion(version))
  }
}

pub fn total_codewords(version: Int) -> Result(Int, EncodeError) {
  case is_valid(version) {
    True -> Ok(util.at_or(total_codewords_table, version, default: 0))
    False -> Error(InvalidVersion(version))
  }
}

pub fn ec_total_codewords(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  lookup_by_ecc(ec_codewords_table, version, ecc)
}

pub fn ec_blocks(version: Int, ecc: ErrorCorrection) -> Result(Int, EncodeError) {
  lookup_by_ecc(ec_blocks_table, version, ecc)
}

pub fn data_codewords(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  case total_codewords(version), ec_total_codewords(version, ecc) {
    Ok(total), Ok(ec) -> Ok(total - ec)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

pub fn data_capacity_bits(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  case data_codewords(version, ecc) {
    Ok(codewords) -> Ok(codewords * 8)
    Error(error) -> Error(error)
  }
}

pub fn best_version_for_bits(
  bits_needed: Int,
  ecc: ErrorCorrection,
  min_version: Int,
) -> Result(Int, EncodeError) {
  do_best_version(bits_needed, ecc, min_version)
}

fn do_best_version(
  bits_needed: Int,
  ecc: ErrorCorrection,
  candidate: Int,
) -> Result(Int, EncodeError) {
  case candidate > 40 {
    True ->
      case data_capacity_bits(40, ecc) {
        Ok(bits_available) ->
          Error(DataExceedsCapacity(bits_needed, bits_available))
        Error(error) -> Error(error)
      }
    False ->
      case data_capacity_bits(candidate, ecc) {
        Ok(bits_available) ->
          case bits_needed <= bits_available {
            True -> Ok(candidate)
            False -> do_best_version(bits_needed, ecc, candidate + 1)
          }
        Error(error) -> Error(error)
      }
  }
}

fn lookup_by_ecc(
  table: List(Int),
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  case is_valid(version) {
    False -> Error(InvalidVersion(version))
    True -> {
      let offset = { version - 1 } * 4 + ecc_index(ecc)
      Ok(util.at_or(table, offset, default: 0))
    }
  }
}

fn ecc_index(ecc: ErrorCorrection) -> Int {
  case ecc {
    Low -> 0
    Medium -> 1
    Quartile -> 2
    High -> 3
  }
}
