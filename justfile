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
  gleam format src/ test/

format-check:
  gleam format --check src/ test/

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
  gleam format --check src/ test/
  gleam check
  gleam run -m glinter
  gleam build --warnings-as-errors
  gleam test

ci: deps clean
  gleam format --check src/ test/
  gleam check
  gleam run -m glinter
  gleam build --warnings-as-errors --target erlang
  gleam build --warnings-as-errors --target javascript
  gleam test --target erlang
  gleam test --target javascript

all: deps clean
  gleam format --check src/ test/
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
