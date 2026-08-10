#!/bin/sh
#
# ./run.sh                 the game, starting at the menu
# RAVEL_SEED=42 ./run.sh   fixed RNG seed, so a run is reproducible
# RAVEL_DEBUG=1 ./run.sh   also opens the debug server on 127.0.0.1:5757
set -eu
cd "$(dirname "$0")"
LOVE="${LOVE:-love}"
command -v "$LOVE" >/dev/null 2>&1 || LOVE="$HOME/.local/bin/love"
command -v "$LOVE" >/dev/null 2>&1 || {
	echo "run.sh: no love binary on PATH or in ~/.local/bin — set LOVE=/path/to/love" >&2
	exit 1
}
exec "$LOVE" game "$@"
