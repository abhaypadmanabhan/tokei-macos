#!/usr/bin/env bash
# watch.sh <max-seconds> <name:lane> ... — exits on the first event: a result file with a STATUS line,
# a worker whose turn ended (not "working") on two polls in a row, or the time limit.
RUN=/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14
max=$1; shift
tmp=$(mktemp -d)
end=$(( $(date +%s) + max ))
while [ "$(date +%s)" -lt "$end" ]; do
  for pair in "$@"; do
    name=${pair%%:*}; lane=${pair#*:}
    case "$lane" in *.md) f="$RUN/$lane" ;; *) f="$RUN/${lane}.result.md" ;; esac
    res=$(ls "$f" 2>/dev/null | head -1)
    if [ -n "$res" ] && head -1 "$res" | grep -q '^STATUS:'; then
      echo "EVENT result $name $(head -1 "$res")"; exit 0
    fi
    case "$name" in _*) continue ;; esac
    st=$(herdr agent get "$name" 2>/dev/null | grep -o '"agent_status":"[^"]*"' | cut -d'"' -f4)
    if [ "$st" != "working" ]; then
      n=$(( $(cat "$tmp/$name" 2>/dev/null || echo 0) + 1 )); echo $n > "$tmp/$name"
      if [ "$n" -ge 2 ]; then echo "EVENT status $name ${st:-unknown}"; exit 0; fi
    else
      echo 0 > "$tmp/$name"
    fi
  done
  sleep 60
done
echo "EVENT heartbeat $(date +%H:%M)"
