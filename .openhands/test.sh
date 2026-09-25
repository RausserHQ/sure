#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/.openhands/activate.sh"
cd "$root"

: "${TEST_POSTGRES_HOST:?OpenHands shared PostgreSQL host is required}"
: "${TEST_POSTGRES_USER:?OpenHands shared PostgreSQL user is required}"
: "${TEST_POSTGRES_PASSWORD:?OpenHands shared PostgreSQL password is required}"

if [[ "$#" -eq 0 ]]; then set -- bin/rails test; fi
bundle exec ruby "$root/.openhands/with_test_db.rb" "$@"
