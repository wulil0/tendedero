#!/bin/bash
# Builds Tendedero.app, installs it in /Applications in place of the copy
# there, and opens it. The build is signed as scripts/build-app.sh signs it:
# with the local "Tendedero Local" certificate when there is one, so macOS
# keeps the app's permissions from one build to the next.
# Usage: scripts/install.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh "${1:-release}"

# Quit the running copy first, so the new one is the one that runs.
pkill -x Tendedero || true
sleep 1
rm -rf /Applications/Tendedero.app
# Moved, not copied, so Spotlight finds one Tendedero and not two.
mv build/Tendedero.app /Applications/
open /Applications/Tendedero.app
echo "Installed /Applications/Tendedero.app"
