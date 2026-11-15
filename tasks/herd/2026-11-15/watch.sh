#!/usr/bin/env bash
# watch.sh <max-seconds> — exits on the first event: a result or review file with a STATUS/VERDICT first line
# that is not yet listed in .seen, a child of t1d that is not "working" on two polls in a row, or the time limit.
RUN=/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15
touch "$RUN/.seen"; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
end=$(( $(date +%s) + ${1:-580} ))
while [ "$(date +%s)" -lt "$end" ]; do
  for f in "$RUN"/*.result.md "$RUN"/*-review-r*.md "$RUN"/*-fix-r*.done; do
    [ -f "$f" ] || continue
    key="$(basename "$f") $(shasum "$f" | cut -c1-12)"
    if head -1 "$f" | grep -qE '^(STATUS|VERDICT):' && ! grep -qxF "$key" "$RUN/.seen"; then
      echo "$key" >> "$RUN/.seen"; echo "EVENT file $(basename "$f") $(head -1 "$f")"; exit 0
    fi
  done
  hc ls 2>/dev/null | python3 -c "
import sys,json
for t in json.load(sys.stdin)['terminals']:
    if t.get('parent')=='t1d': print(t['address'],t.get('name'),t.get('status') or t.get('state'))" > "$tmp/now"
  while read -r addr name st; do
    if [ "$st" != "working" ]; then
      n=$(( $(cat "$tmp/$addr" 2>/dev/null || echo 0) + 1 )); echo $n > "$tmp/$addr"
      if [ "$n" -ge 2 ] && ! grep -qxF "idle $addr $st" "$RUN/.seen"; then echo "EVENT status $addr $name $st"; exit 0; fi
    else echo 0 > "$tmp/$addr"; fi
  done < "$tmp/now"
  sleep 45
done
echo "EVENT heartbeat $(date +%H:%M)"
