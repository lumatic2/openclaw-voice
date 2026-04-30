#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
# Load local secrets (BRIDGE_AUTH_TOKEN, optional NVM_DIR) if present
if [ -f "$DIR/.env" ]; then
  set -a
  . "$DIR/.env"
  set +a
fi
# Use nvm-installed node if available, otherwise system node
if [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
fi
# Auto-install dependencies on fresh checkout / new working directory
if [ ! -d "$DIR/node_modules" ]; then
  npm install --omit=dev --no-audit --no-fund
fi
exec node server.js
