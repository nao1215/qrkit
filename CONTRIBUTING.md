# Contributing to qrkit

## Development setup

You need the following tools installed:

- [Gleam](https://gleam.run/) 1.15+
- Erlang/OTP 28+
- Node.js 22+ for JavaScript-target builds and tests
- [just](https://github.com/casey/just) as a task runner
- [mise](https://mise.jdx.dev/) for toolchain management

Clone the repository and install the managed toolchain:

```console
git clone https://github.com/nao1215/qrkit.git
cd qrkit
mise trust .mise.toml
mise install
just deps
```

`just` recipes and helper scripts locate the mise-managed toolchain via
`scripts/lib/mise_bootstrap.sh`, so `mise activate` is not required in
the current shell.

## Running checks

Run the full CI-equivalent check locally with:

```console
just ci
```

This runs format check, type check, lint, Erlang-target build and test,
and JavaScript-target build and test.

You can also run individual steps:

| Command | Effect |
| --- | --- |
| `just format` | Reformat `src/` and `test/` |
| `just format-check` | Fail on formatting drift |
| `just typecheck` | `gleam check` |
| `just lint` | Run `glinter` with warnings as errors |
| `just build-erlang` / `just build-javascript` | Per-target build |
| `just test-erlang` / `just test-javascript` | Per-target test |
| `just docs` | Build HexDocs HTML |
| `just clean` | Delete `build/` |

## Project structure

- `src/` contains public library modules
- `test/` contains the `gleeunit` test suite
- `scripts/lib/mise_bootstrap.sh` makes the mise-managed toolchain
  available to `just` and shell scripts
- `.github/workflows/` contains CI and release automation

## Code style

- Run `gleam format src/ test/` before committing.
- The build uses `--warnings-as-errors`; fix all warnings.
- `glinter` runs in `warnings_as_errors` mode. Rule changes in
  `gleam.toml` require a justification.
- Public API (`pub fn`, `pub type`, public constants) requires doc
  comments.
- Prefer pure Gleam over target-specific FFI.
- Keep cross-target behavior aligned unless target-specific behavior is
  explicitly documented.
- Keep the public API small, deterministic, and QR-domain focused.

## Testing expectations

- Add unit tests for new public behavior.
- Run target-neutral tests on both Erlang and JavaScript targets.
- Reflect user-visible behavior changes in README examples or doc
  comments.

## Pull request expectations

- All CI checks must pass (`just ci`).
- Include tests for new behavior.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for
  commit messages (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`, ...).
- One logical change per pull request.

## Release process

Releases are cut from `main` and driven entirely by tag pushes. The
`.github/workflows/release.yml` workflow runs the full check matrix,
publishes to Hex, and creates a GitHub Release whose body is extracted
from `CHANGELOG.md`.

Steps for a new release `vX.Y.Z`:

1. Confirm `main` is green on CI and the working tree is clean.
2. Promote any items under `## Unreleased` in `CHANGELOG.md` into a
   new `## [X.Y.Z] - YYYY-MM-DD` section directly below `## Unreleased`.
3. Bump `version = "X.Y.Z"` in `gleam.toml`.
4. Open a PR with the changelog and version bump, get it green and
   merged.
5. After merge, fast-forward `main` and tag the merge commit:
   ```console
   git checkout main
   git pull --ff-only origin main
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
6. The release workflow handles `gleam publish` and the GitHub Release.

## License

Contributions to this project are considered to be released under the
project license (MIT).
