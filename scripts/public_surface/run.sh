#!/bin/zsh
# The census of Tempo's exported functions: what each is documented as, and
# who calls it. Writes plans/public-surface-census.md. Run from the
# repository root: `zsh scripts/public_surface/run.sh`. It recompiles the
# library and the tests (about four minutes), and runs no test. With
# `SURFACE_WORK` naming a directory, the calls recorded there by an earlier
# run are read again and nothing is recompiled.
set -e
here=${0:A:h}
work=${SURFACE_WORK:-$(mktemp -d)}
mkdir -p "${work}"
export LOCALIZE_DEFAULT_LOCALE=en MIX_ENV=test

if [[ ! -s "${work}/calls_test.tsv" ]]; then
# The calls the library makes, recorded as it compiles.
export SURFACE_CALLS="${work}/calls_lib.tsv"
: > "${SURFACE_CALLS}"
elixir -r "${here}/tracer.exs" -S mix compile --force --tracer PublicSurface.Tracer > "${work}/compile.out" 2>&1

# The calls the tests make: the test files are compiled, and none is run.
export SURFACE_CALLS="${work}/calls_test.tsv"
: > "${SURFACE_CALLS}"
elixir -r "${here}/tracer.exs" -e 'Code.put_compiler_option(:tracers, [PublicSurface.Tracer])' \
  -S mix test --only no_such_tag > "${work}/tests.out" 2>&1 || true
fi

# What each module exports.
SURFACE_EXPORTS="${work}/exports.tsv" mix run --no-start "${here}/exports.exs" > "${work}/exports.out" 2>&1

python3 "${here}/census.py" "${work}" plans/public-surface-census.md
