#!/usr/bin/env bash
set -euo pipefail

info() {
  printf '\n[day0] %s\n' "$1"
}

info "Ensuring asdf tool versions are installed"
asdf install || true
asdf install erlang
asdf install elixir

info "Fetching deps, compiling, and preparing database"
mix deps.get
mix compile
mix ecto.create
mix ecto.migrate

info "Running quality gates"
mix format --check-formatted
mix credo --strict
if ! mix dialyzer; then
  info "Dialyzer PLT missing or stale; rebuilding"
  mix dialyzer --plt
fi
mix sobelow -i Config.HTTPS,Config.CSP
mix hex.audit
if ! mix hex.outdated; then
  mix deps.outdated
fi

info "Executing test suite with coverage"
MIX_ENV=test mix test --cover

info "Day-0 bootstrap complete"
