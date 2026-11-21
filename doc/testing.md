# Testing

`just ci` runs everything below except the nightly jobs. Tests run on the Erlang and JavaScript targets, on the Gleam floor (1.14.0, OTP 27, Node 22) and on the latest Gleam 1.x.

## Examples and unit tests

`test/qrkit_test.gleam` checks module matrices, capacities and errors of the encoder against values from ISO/IEC 18004 and ISO/IEC 23941, and `test/decode_test.gleam` checks the decoder. `test/readme_examples_test.gleam` runs every README snippet. Each fixed bug keeps its reproduction in a `test/regression_*_test.gleam` file.

## Generated properties

`test/property_test.gleam` uses metamon. Encoding then decoding returns the input for every symbol family and error correction level; one flipped module is always corrected; the decoder returns a value instead of crashing for random grids and for heavily damaged symbols. The generators in `test/generators.gleam` mix ASCII, digits, kana, kanji, Latin-1, an emoji and newlines so every mode and segment boundary is reached.

## Metamorphic relations

`test/metamorphic_test.gleam` checks relations between two runs where the exact output cannot be written down:

- Appending a character never yields a smaller symbol, for short payloads in every family and for 150-700 character payloads that cross the version 9/10 and 26/27 boundaries of Standard QR, where the character-count fields get wider.
- Raising the error correction level one step never yields a smaller symbol.
- The decoder reads the same text after a turn by 90, 180 or 270 degrees, a left-right, top-bottom or diagonal mirror and an added light quiet zone, for every symbol family.
- An added quiet zone does not change the version, family, level or mask the decoder reports, and no codeword needs correcting.

## Snapshots

`test/snapshot_test.gleam` uses birdie for the terminal and SVG renderers: Standard QR with Byte, Kanji and Numeric segments, Micro QR and rMQR. The SVG snapshot puts one path command per line so that a changed module is a changed line. Every snapshot symbol is also decoded, so an accepted snapshot is known to read back to its input. Review a changed snapshot with `gleam run -m birdie` before accepting it; the accepted files live in `test/birdie_snapshots/`.

## Differential testing

The nightly `interop` job in `.github/workflows/nightly-property.yml` compares qrkit with independent implementations through `scripts/interop.py`. zxing-cpp must read random symbols qrkit writes (`test/gen/interop_corpus.gleam`), and `qrkit.decode` must read random symbols segno writes the way zxing-cpp reads them (`dev/gen/interop_decode.gleam`). The Python packages are installed from `scripts/interop-requirements.txt` with `pip --require-hashes`.

## Nightly runs

The nightly `property` job runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.

## Mutation testing

There is no mutation testing tool for Gleam, so `gleam_mutate.py` (from the mutation-testing lab in nao1215/debimate) is run by hand on a copy of the project. It rewrites one operator or boolean result at a time (`==`/`!=`, `&&`/`||`, float comparisons, `-> True`/`-> False`, a dropped `!`) and runs `gleam test` on the Erlang target. The score is killed / (killed + lived).

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19 | every module under `src/` | 215 | 51 | 80.8% |

The first run left the three PNG mutants alive (bit packing and CRC-32); `png_renderer_writes_every_module_and_valid_checksums_test` now reads the scanlines back and checks the IEND checksum, and kills them. The remaining survivors, grouped:

- `decode.guess_shift_jis` (14): Byte data without an ECI that is valid UTF-8 and Shift JIS at once. qrkit always writes Kanji mode for such text, so only symbols from other writers reach it; the nightly interop job reads segno symbols.
- The data masks 1 and 5 of Standard QR and mask 2 of Micro QR (3): the encoder and decoder share `mask_at`, so an inverted pattern still round-trips. Only the nightly zxing-cpp check would see it.
- `micro.mode_supported` (3): the segmenter picks a supported mode before this check runs, so returning False only changes which equivalent path is taken.
- `content.is_some_delim` and `is_unreserved_punct` (7): turning them off percent-encodes characters that may stay literal in a mailto URI. The result is still a valid URI, and no test pins the literal form.
- Range checks written as `a && b` or `a || b` on values the caller has already validated (`version.is_valid`, `dimensions`, `validate_version`, `finder_overlap` and others).
