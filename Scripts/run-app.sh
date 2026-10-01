#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

"$DIR/Scripts/build-app.sh" "$@"

echo "🚀 Stopping any previously running AMORA process..."
killall AMORA 2>/dev/null || true
sleep 0.5

echo "✨ Launching AMORA.app..."
open "$DIR/AMORA.app"

echo "🌟 AMORA is running!"
