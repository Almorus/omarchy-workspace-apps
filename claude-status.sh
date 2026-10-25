#!/bin/sh
# Claude Code hook: records what this session is doing for the bar widget.
# Usage: claude-status.sh working|input|idle, with the hook's JSON on stdin.
# Writes "<state> <transcript>" to $XDG_RUNTIME_DIR/agent-status/claude-<pid>
# (idle removes it) and bumps the `changed` file so the widget rescans.
# It never prints or fails, so it can't get in Claude Code's way.
state=$1
run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
[ -d "$run" ] || exit 0
dir=$run/agent-status

# The claude process this hook runs under, a few parents up at most.
pid=$PPID
i=0
while [ "$i" -lt 8 ] && [ "$(cat "/proc/$pid/comm" 2>/dev/null)" != claude ]; do
  pid=$(awk '$1 == "PPid:" { print $2 }' "/proc/$pid/status" 2>/dev/null)
  [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || exit 0
  i=$((i + 1))
done
[ "$(cat "/proc/$pid/comm" 2>/dev/null)" = claude ] || exit 0
file=$dir/claude-$pid

case $state in
  working|input)
    read -r old _ 2>/dev/null < "$file"
    [ "$old" = "$state" ] && exit 0
    transcript=$(jq -r '.transcript_path // empty' 2>/dev/null)
    mkdir -p "$dir" 2>/dev/null || exit 0
    printf '%s %s\n' "$state" "$transcript" 2>/dev/null > "$file.$$" && mv -f "$file.$$" "$file" 2>/dev/null
    ;;
  *)
    [ -e "$file" ] || exit 0
    rm -f "$file"
    ;;
esac
printf 'claude-%s %s\n' "$pid" "$state" 2>/dev/null > "$dir/changed"
exit 0
