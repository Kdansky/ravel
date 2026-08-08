#!/bin/sh
set -eu

GAME_DIR="${GAME_DIR:-/workspace/game}"
OUTPUT="${OUTPUT:-/usr/share/nginx/html/game.love}"

pack_game() {
  tmpdir="$(mktemp -d /tmp/game.XXXXXX)"
  tmpfile="$tmpdir/game.love"
  (
    cd "$GAME_DIR"
    zip -q -9 -r "$tmpfile" . -x '*.DS_Store'
  )
  mv "$tmpfile" "$OUTPUT"
  rmdir "$tmpdir"
  echo "Packed $GAME_DIR -> $OUTPUT"
}

fingerprint_game() {
  find "$GAME_DIR" -type f ! -name '.DS_Store' -exec stat -c '%n %Y %s' {} \; | sort | sha1sum | awk '{print $1}'
}

# Deliberately outside "set -e": one transient failure — a file the editor is
# in the middle of replacing, so stat exits non-zero — used to kill this loop
# silently, and the only symptom is that the browser keeps serving whatever was
# packed when the container started. An empty fingerprint means the scan failed
# rather than that the directory is empty, so it is skipped rather than acted on.
watch_game() {
  set +e
  last_fingerprint="$(fingerprint_game)"
  while sleep 1; do
    current_fingerprint="$(fingerprint_game)"
    if [ -n "$current_fingerprint" ] && [ "$current_fingerprint" != "$last_fingerprint" ]; then
      pack_game && last_fingerprint="$current_fingerprint"
    fi
  done
}

pack_game
watch_game &
WATCHER=$!

# nginx runs in the foreground but not as PID 1, so the watcher can be reaped
# with it. Under "exec nginx" the watcher was orphaned onto the new PID 1 and
# outlived nothing — it simply stopped, with no log line to say so.
nginx -g "daemon off;" &
NGINX=$!
trap 'kill "$WATCHER" "$NGINX" 2>/dev/null' INT TERM
wait "$NGINX"
