#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ruby_version="$(tr -d '[:space:]' < "$root/.ruby-version")"
bundler_version="$(awk '/^BUNDLED WITH$/{getline; gsub(/^[[:space:]]+/, ""); print}' "$root/Gemfile.lock")"
mise_version="2026.9.11"
mise_bin="$HOME/.local/bin/mise"
cache_dir="$HOME/.cache/sure-openhands"

[[ "$ruby_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid .ruby-version pin" >&2; exit 1; }
[[ -n "$bundler_version" ]] || { echo "Missing Bundler pin in Gemfile.lock" >&2; exit 1; }
for tool in curl tar git gcc make pkg-config flock sha256sum; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
if ! command -v pg_config >/dev/null; then echo "Missing libpq development tools (pg_config)" >&2; exit 1; fi
if pkg-config --exists vips; then
  echo "libvips development files available"
else
  echo "libvips development files absent; checking the runtime after gem installation"
fi

mkdir -p "$cache_dir" "$HOME/.local/bin"
exec 9>"$cache_dir/setup.lock"
flock 9

if [[ ! -x "$mise_bin" ]] || [[ "$("$mise_bin" --version 2>/dev/null)" != *"$mise_version"* ]]; then
  # The official installer verifies its release checksums and installs as this user.
  curl -fsSL https://mise.run | MISE_VERSION="$mise_version" sh
fi

"$mise_bin" install "ruby@$ruby_version" node@24
source "$root/.openhands/activate.sh"

if ! gem list --local --exact bundler --version "$bundler_version" | grep -q '^bundler '; then
  gem install bundler --version "$bundler_version" --no-document
fi

cd "$root"
if ! bundle check >/dev/null 2>&1; then
  bundle install --jobs 4 --retry 3
fi
bundle exec ruby -e 'require "vips"; puts "libvips runtime available"'

lock_hash="$(sha256sum package-lock.json | cut -d ' ' -f 1)"
node_version="$(node --version)"
npm_marker="$cache_dir/npm-$(printf '%s' "$root" | sha256sum | cut -d ' ' -f 1)"
if [[ ! -x node_modules/.bin/biome ]] || [[ "$(cat "$npm_marker" 2>/dev/null || true)" != "$lock_hash $node_version" ]]; then
  rm -f "$npm_marker"
  npm ci --prefer-offline --no-audit --no-fund
  printf '%s %s\n' "$lock_hash" "$node_version" > "$npm_marker"
fi

for profile in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
  line="if [ -n \"\${BASH_VERSION:-}\${ZSH_VERSION:-}\" ]; then . '$root/.openhands/activate.sh'; fi # sure-openhands"
  touch "$profile"
  if ! grep -Fqx "$line" "$profile"; then printf '\n%s\n' "$line" >> "$profile"; fi
done

echo "OpenHands setup ready: Ruby $(ruby --version), Bundler $(bundle --version), Node $(node --version), npm $(npm --version)"
echo "For non-interactive shells: source '$root/.openhands/activate.sh'"
