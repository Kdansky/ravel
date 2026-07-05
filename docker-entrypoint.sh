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

watch_game() {
  last_fingerprint="$(fingerprint_game)"
  while true; do
    sleep 1
    current_fingerprint="$(fingerprint_game)"
    if [ "$current_fingerprint" != "$last_fingerprint" ]; then
      pack_game
      last_fingerprint="$current_fingerprint"
    fi
  done
}

pack_game
watch_game &

exec nginx -g "daemon off;"
