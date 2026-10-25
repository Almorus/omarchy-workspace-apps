#!/bin/sh
# Report what the agents in your windows are doing:
#   window <address> <state>  every window with a `claude` process under it
#                             (address without 0x)
#   app hermes <state>        Hermes as a whole
# The state is idle, working or input, as recorded by claude-status.sh and
# hermes-status.sh from the agents' hooks; without hooks everything is idle.
# Claude Code inside tmux counts for the terminals attached to that tmux
# session. Workspaces.qml decides which of these windows are terminals.
run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
dir=$run/agent-status

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
if [ -d "$run" ] && mkdir -p "$dir" 2>/dev/null; then
  [ -e "$dir/changed" ] || : > "$dir/changed"
fi

# Hermes runs its agents in a background gateway rather than under its window,
# so it gets one state: the most urgent of any running Hermes process.
hermes=idle
for f in "$dir"/hermes-*; do
  pid=${f##*/hermes-}
  case $pid in ''|*[!0-9]*) continue ;; esac
  # Left behind by a Hermes that crashed or was stopped mid-turn.
  if ! tr '\0' ' ' 2>/dev/null < "/proc/$pid/cmdline" | grep -q hermes; then rm -f "$f"; continue; fi
  read -r state < "$f" || continue
  case $state in
    input) hermes=input ;;
    working) [ "$hermes" = input ] || hermes=working ;;
  esac
done
echo "app hermes $hermes"

{
  for f in "$dir"/claude-*; do
    pid=${f##*/claude-}
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
  $1 == "pid:" && ($2 in anc) { print "window", w, name[anc[$2]] }
'
