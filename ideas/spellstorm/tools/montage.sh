#!/bin/bash
# Tile a folder of card images 2x2 into readable sheets for transcription.
set -e
dir="$1"; out="$2"; shift 2
mkdir -p "$out"
ls "$dir"/*.jpg | sort > /tmp/_cards.txt
split -l 4 -d /tmp/_cards.txt /tmp/_chunk_
for c in /tmp/_chunk_*; do
  n=$(basename "$c" | sed 's/_chunk_//')
  magick montage $(cat "$c" | tr '\n' ' ') -tile 2x2 -geometry 700x955+6+6 -background '#333' "$out/sheet-$n.jpg"
  echo "sheet-$n: $(cat "$c" | xargs -n1 basename | tr '\n' ' ')"
done
rm -f /tmp/_chunk_* /tmp/_cards.txt
