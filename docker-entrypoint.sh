#!/bin/sh
set -eu

GAME_DIR="${GAME_DIR:-/workspace/game}"
OUTPUT="${OUTPUT:-/usr/share/nginx/html/game.love}"

# A stale bind mount reads as an *empty directory*, never as an error — and an
# empty directory has a perfectly good fingerprint, so the watcher below sees a
# change, packs nothing, and replaces a working build with one that cannot
# start. The browser meets that as "Cannot read game file: menu.json", three
# layers away from the cause, and the game.love keeps being served with a 200.
#
# So: never overwrite a build with something that is not a game. This is the
# same class of silent failure the watcher comment below describes, and the
# reason it was not already caught is that "empty" and "broken" look identical
# from a fingerprint.
game_is_there() {
  [ -f "$GAME_DIR/main.lua" ] && [ -f "$GAME_DIR/games/menu.json" ]
}

pack_game() {
  if ! game_is_there; then
    echo "Refusing to pack: $GAME_DIR holds no main.lua and games/menu.json." >&2
    echo "  The bind mount has probably gone stale. Recreate the container:" >&2
    echo "    docker compose up -d --force-recreate" >&2
    return 1
  fi
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

# Not fatal: nginx should come up and say 404 rather than the container
# crash-looping, which hides the message above in a wall of restarts.
pack_game || true
watch_game &
WATCHER=$!

# nginx runs in the foreground but not as PID 1, so the watcher can be reaped
# with it. Under "exec nginx" the watcher was orphaned onto the new PID 1 and
# outlived nothing — it simply stopped, with no log line to say so.
nginx -g "daemon off;" &
NGINX=$!
trap 'kill "$WATCHER" "$NGINX" 2>/dev/null' INT TERM
wait "$NGINX"
