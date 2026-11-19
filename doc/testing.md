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

The nightly `interop` job in `.github/workflows/nightly-property.yml` compares qrkit with independent implementations through `scripts/interop.py`. zxing-cpp must read random symbols qrkit writes (`test/gen/interop_corpus.gleam`), and qrkit/decode must read random symbols segno writes the way zxing-cpp reads them (`test/gen/interop_decode.gleam`). The Python packages are installed from `scripts/interop-requirements.txt` with `pip --require-hashes`.

## Nightly runs

The nightly `property` job runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.
