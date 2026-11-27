set shell := ["sh", "-cu"]

# Make the mise-managed toolchain (erlang / gleam / rebar / node)
# visible to every recipe even when the invoking shell has not run
# `mise activate`.
export PATH := `sh -cu '. scripts/lib/mise_bootstrap.sh; printf %s "$PATH"'`

default:
  @just --list

deps:
  gleam deps download

format:
  gleam format src/ test/ dev/

format-check:
  gleam format --check src/ test/ dev/

lint:
  gleam run -m glinter

typecheck:
  gleam check

build:
  gleam build --warnings-as-errors

build-erlang:
  gleam build --warnings-as-errors --target erlang

build-javascript:
  gleam build --warnings-as-errors --target javascript

build-all-targets: build-erlang build-javascript

test:
  gleam test

test-erlang:
  gleam test --target erlang

test-javascript:
  gleam test --target javascript

test-all-targets: test-erlang test-javascript

docs:
  gleam docs build

check: deps clean
  gleam format --check src/ test/ dev/
  gleam check
  gleam run -m glinter
  gleam build --warnings-as-errors
  gleam test

ci: deps clean
  gleam format --check src/ test/ dev/
  gleam check
  gleam run -m glinter
  gleam build --warnings-as-errors --target erlang
  gleam build --warnings-as-errors --target javascript
  gleam test --target erlang
  gleam test --target javascript

all: deps clean
  gleam format --check src/ test/ dev/
  gleam check
  gleam run -m glinter
  gleam build --warnings-as-errors --target erlang
  gleam build --warnings-as-errors --target javascript
  gleam test --target erlang
  gleam test --target javascript
  gleam docs build
  @echo ""
  @echo "All checks passed."

clean:
  gleam clean

# Python with the packages in scripts/interop-requirements.txt and libzbar0.
python := env("PYTHON", "python3")

# `runs` corpora of qrkit symbols are joined; `segno` is the number of segno
# symbols qrkit must read. Fails when a gated group disagrees.
# Differential testing against zxing-cpp, zbar and segno
interop runs="1" segno="600":
  rm -rf build/interop && mkdir -p build/interop
  for i in $(seq {{runs}}); do gleam run -m gen/interop_corpus || exit 1; cat build/interop/qrkit.tsv >> build/interop/all.tsv; done
  {{python}} scripts/interop.py read zxing build/interop/all.tsv build/interop/zxing.tsv
  {{python}} scripts/interop.py read zbar build/interop/all.tsv build/interop/zbar.tsv
  {{python}} scripts/interop.py segno build/interop/segno.tsv {{segno}}
  gleam run -m interop -- check

# Run interop on a large corpus and record it in doc/interop.md
interop-record: (interop "10" "5000")
  gleam run -m interop -- record

# Slow: run it on a machine with many cores, then `just mutation-record`.
# Mutation testing of every module, failing on survivors the baseline lacks
mutation workers="8":
  gleam run -m mutation -- run --workers {{workers}}
  gleam run -m mutation -- gate

# Record the last mutation run as the baseline in doc/
mutation-record:
  gleam run -m mutation -- baseline

# Check that the generated tables and figures match the code and results
doc-check:
  gleam run -m interop -- doc-check
  gleam run -m mutation -- doc-check
  gleam run -m gen/doc_images
  test -z "$(git status --porcelain -- docs/images)" || { git status --short -- docs/images; exit 1; }
