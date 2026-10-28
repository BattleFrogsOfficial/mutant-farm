#!/usr/bin/env bash
# Installs the command-line tools this repo needs (pinned to the versions it was built and checked
# with) from crates.io via cargo, plus the preview renderer's npm packages. Safe to re-run: cargo
# skips tools already at the right version. Use it as (or from) a cloud environment setup script.
#   lune 0.11.1   tests, simulator, checks, UI/world preview export
#   rojo 7.7.1    builds the place file
#   stylua 2.6.0  formatting
#   selene 0.31.0 linting (needs `selene generate-roblox-std` once, with internet)
set -euo pipefail

if ! command -v cargo >/dev/null 2>&1; then
	curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
	. "$HOME/.cargo/env"
fi
export PATH="$HOME/.cargo/bin:$PATH"

cargo install --locked lune --version 0.11.1
cargo install --locked rojo --version 7.7.1
cargo install --locked stylua --version 2.6.0 --features luau # without the feature it cannot parse Luau
cargo install --locked selene --version 0.31.0

# Preview renderers (Chromium + Playwright are preinstalled in cloud sessions).
repo="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$repo/tools/preview/package.json" ]; then
	(cd "$repo/tools/preview" && npm install --no-audit --no-fund)
fi

lune --version && rojo --version && stylua --version && selene --version
