#!/bin/sh
# Print "<address> <state>" (address without 0x) for every window with a
# `claude` process under it. Claude Code inside tmux counts for the terminals
# attached to that tmux session. The state is idle, working or input, as
# recorded by claude-status.sh from Claude Code's hooks; without the hooks every
# session is idle. Workspaces.qml decides which of these windows are terminals.
dir=${XDG_RUNTIME_DIR:-}/claude-status

# Pressing Esc in Claude Code runs no hook. If the transcript was written after
# the state and its last message is that interrupt, the session is idle.
interrupted() {
  [ -n "$2" ] && [ "$2" -nt "$1" ] || return 1
  tail -c 65536 "$2" 2>/dev/null |
    jq -rR 'fromjson? | select(.type == "user" or .type == "assistant")
      | .type + " " + (.message.content | if type == "array" then map(.text? // empty) | join(" ") else tostring end)' 2>/dev/null |
    tail -n 1 | grep -q '^user \[Request interrupted by user'
}

# The widget watches `changed`, which has to exist before anything is written.
if [ -n "${XDG_RUNTIME_DIR:-}" ] && mkdir -p "$dir" 2>/dev/null; then
  [ -e "$dir/changed" ] || : > "$dir/changed"
fi

{
  for f in "$dir"/*; do
    pid=${f##*/}
    case $pid in ''|*[!0-9]*) continue ;; esac
    # Left behind by a session that crashed or was killed.
    if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" != claude ]; then rm -f "$f"; continue; fi
    read -r state transcript < "$f" || continue
    interrupted "$f" "$transcript" && state=idle
    echo "S $pid $state"
  done
  ps -eo pid=,ppid=,comm= | sed 's/^/P /'
  tmux list-panes -a -F 'T #{pane_pid} #{session_id}' 2>/dev/null
  tmux list-clients -F 'C #{client_pid} #{session_id}' 2>/dev/null
  hyprctl clients
} | awk '
  BEGIN { rank["working"] = 2; rank["input"] = 3; name[1] = "idle"; name[2] = "working"; name[3] = "input" }
  $1 == "S" { st[$2] = ($3 in rank) ? rank[$3] : 1; next }
  $1 == "P" { par[$2] = $3; if ($4 == "claude") claude[$2] = ($2 in st) ? st[$2] : 1; next }
  $1 == "T" { pane[$2] = $3; next }
  $1 == "C" { client[$2] = $3; next }
  !done {
    # tmux sessions with Claude Code in one of their panes, at their most
    # urgent state (input over working over idle)
    for (p in claude) {
      q = p
      for (i = 0; i < 20 && q > 1; i++) {
        if ((q in pane) && claude[p] > hot[pane[q]]) hot[pane[q]] = claude[p]
        q = par[q]
      }
    }
    # a tmux client showing such a session stands in for the claude process
    for (c in client) if ((client[c] in hot) && hot[client[c]] > claude[c]) claude[c] = hot[client[c]]
    for (p in claude) {
      q = par[p]
      for (i = 0; i < 10 && q > 1; i++) { if (claude[p] > anc[q]) anc[q] = claude[p]; q = par[q] }
    }
    done = 1
  }
  $1 == "Window" { w = $2 }
  $1 == "pid:" && ($2 in anc) { print w, name[anc[$2]] }
'
