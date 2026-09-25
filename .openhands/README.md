# OpenHands setup for this fork

Run `.openhands/setup.sh` in a fresh OpenHands sandbox. It installs the Ruby version
from `.ruby-version`, Bundler from `Gemfile.lock`, Node 24, gems, and locked npm
packages as the current user. It checks compiler and libpq prerequisites before
installing, then verifies the libvips runtime through Ruby. Subsequent runs reuse
installed tools and dependencies. The setup script does not start services or
prepare a database.

New interactive shells source `.openhands/activate.sh` through the user shell
profiles. In non-interactive shells, source it explicitly. This puts the repository
bin directories and installed toolchains on `PATH` and sets the shared Bundler cache.

OpenHands provides `TEST_POSTGRES_HOST`, `TEST_POSTGRES_USER`, and
`TEST_POSTGRES_PASSWORD`. Run tests or checks against the shared disposable service:

```sh
.openhands/test.sh bin/rails test test/models/account_test.rb
bin/rubocop
npm run lint
```

Each invocation creates a random, private test database, loads Sure's schema, runs
the command, and drops only that database. Commands that do not need a database can
run directly after activation. The wrapper disables Rails parallel workers so they
cannot create extra databases on the shared service. It requires the shared service
credentials and never uses the default `sure_test` database.

This directory is fork-only infrastructure for RausserHQ/sure issue #2. Keep it out
of the upstream issue #1 pull request.
