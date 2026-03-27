#!/bin/bash
set -euo pipefail
cd "$HOME/projects/ptt-voice-app/bridge"
exec /usr/bin/env node server.js