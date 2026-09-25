#!/usr/bin/env bash
# Source this file in a new non-interactive shell before running repo commands.
if [ -n "${BASH_VERSION:-}" ]; then
  sure_oh_source="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  eval 'sure_oh_source=${(%):-%x}'
else
  echo "Activate Sure from bash or zsh" >&2
  return 1
fi
sure_oh_root="$(cd "$(dirname "$sure_oh_source")/.." && pwd)"
sure_oh_mise="$HOME/.local/bin/mise"
sure_oh_ruby="$(tr -d '[:space:]' < "$sure_oh_root/.ruby-version")"
sure_oh_ruby_home="$("$sure_oh_mise" where "ruby@$sure_oh_ruby")"
sure_oh_node_home="$("$sure_oh_mise" where node@24)"
export BUNDLE_PATH="$HOME/.cache/sure-openhands/bundle"
export PATH="$sure_oh_root/node_modules/.bin:$sure_oh_root/bin:$sure_oh_node_home/bin:$sure_oh_ruby_home/bin:$HOME/.local/bin:$PATH"
unset sure_oh_source sure_oh_root sure_oh_mise sure_oh_ruby sure_oh_ruby_home sure_oh_node_home
