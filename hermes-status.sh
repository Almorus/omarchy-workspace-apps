#!/bin/sh
# Hermes shell hook: records what Hermes is doing for the bar widget.
# Usage: hermes-status.sh working|input|idle (Hermes's JSON payload on stdin
# isn't needed). Writes the state to $XDG_RUNTIME_DIR/agent-status/hermes-<pid>,
# keyed by the Hermes process that runs the hook (idle removes it), and bumps
# the `changed` file so the widget rescans. It never prints or fails, so Hermes
# carries on as usual.
state=$1
run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
[ -d "$run" ] || exit 0
dir=$run/agent-status

case $PPID in ''|*[!0-9]*) exit 0 ;; esac
file=$dir/hermes-$PPID

case $state in
  working|input)
    read -r old 2>/dev/null < "$file"
    [ "$old" = "$state" ] && exit 0
    mkdir -p "$dir" 2>/dev/null || exit 0
    printf '%s\n' "$state" 2>/dev/null > "$file.$$" && mv -f "$file.$$" "$file" 2>/dev/null
    ;;
  *)
    [ -e "$file" ] || exit 0
    rm -f "$file"
    ;;
esac
printf 'hermes-%s %s\n' "$PPID" "$state" 2>/dev/null > "$dir/changed"
exit 0
