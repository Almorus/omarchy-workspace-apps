#!/bin/sh
# Report what the agents in your windows are doing:
#   window <address> <state>  every window with a `claude` process under it
#                             (address without 0x)
#   hermes <address> <state>  every window with a `hermes` process under it
#   app hermes <state>        Hermes outside any window (the desktop app's
#                             background gateway)
#   prog <address> <program>  the program in the foreground of a window's
#                             terminal, unless that's a shell or an agent
# The state is idle, working or input, as recorded by claude-status.sh and
# hermes-status.sh from the agents' hooks; without hooks everything is idle.
# An agent inside tmux counts for the terminals attached to that tmux
# session, and a tmux client's program is the one in its session's active
# pane. Workspaces.qml decides which of these windows are terminals.
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

{
  # Hermes records its state under the process that ran the hook.
  for f in "$dir"/hermes-*; do
    pid=${f##*/hermes-}
    case $pid in ''|*[!0-9]*) continue ;; esac
    # Left behind by a Hermes that crashed or was stopped mid-turn.
    if ! tr '\0' ' ' 2>/dev/null < "/proc/$pid/cmdline" | grep -q hermes; then rm -f "$f"; continue; fi
    read -r state < "$f" || continue
    echo "H $pid $state"
  done
  for f in "$dir"/claude-*; do
    pid=${f##*/claude-}
    case $pid in ''|*[!0-9]*) continue ;; esac
    # Left behind by a session that crashed or was killed.
    if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" != claude ]; then rm -f "$f"; continue; fi
    read -r state transcript < "$f" || continue
    interrupted "$f" "$transcript" && state=idle
    echo "S $pid $state"
  done
  ps -eo pid=,ppid=,tpgid=,comm= | sed 's/^/P /'
  tmux list-panes -a -F 'T #{pane_pid} #{session_id} #{window_active}#{pane_active} #{pane_current_command}' 2>/dev/null
  tmux list-clients -F 'C #{client_pid} #{session_id}' 2>/dev/null
  hyprctl clients
} | awk '
  # The foreground program of the terminal a window runs (pid w): its one
  # child on a terminal leads that terminal, and the terminal knows its
  # foreground process group. Terminals serving several windows from one
  # process have several such children, so they get none.
  function program(w,   kid, n, i, c, f, p) {
    n = split(kids[w], kid, " ")
    for (i = 1; i <= n; i++) if (fg[kid[i]] > 0) { c++; f = fg[kid[i]] }
    if (c != 1) return ""
    p = (f in client) ? active[client[f]] : comm[f]
    return p ~ /^-?((ba|da|fi|k|z|c|tc)?sh|nu|xonsh|claude|hermes)$/ ? "" : p
  }
  BEGIN {
    rank["working"] = 2; rank["input"] = 3; name[1] = "idle"; name[2] = "working"; name[3] = "input"
    kinds["claude"] = kinds["hermes"] = 1
  }
  # agent[kind, pid]: every claude or hermes process, and every process that
  # ran a Hermes hook, at the rank of its state
  $1 == "S" { st["claude", $2] = ($3 in rank) ? rank[$3] : 1; next }
  $1 == "H" { st["hermes", $2] = ($3 in rank) ? rank[$3] : 1; hook[$2] = 1; next }
  $1 == "P" {
    par[$2] = $3; fg[$2] = $4; kids[$3] = kids[$3] " " $2
    c = $0; sub(/^P +[0-9]+ +[0-9]+ +-?[0-9]+ +/, "", c); comm[$2] = c
    if (c in kinds) agent[c, $2] = ((c, $2) in st) ? st[c, $2] : 1
    next
  }
  $1 == "T" { pane[$2] = $3; if ($4 == "11") active[$3] = $5; next }
  $1 == "C" { client[$2] = $3; next }
  !done {
    for (k in st) if (!(k in agent)) agent[k] = st[k]
    # tmux sessions with an agent in one of their panes, at its most urgent
    # state (input over working over idle)
    for (k in agent) {
      split(k, a, SUBSEP); q = a[2]
      for (i = 0; i < 20 && q > 1; i++) {
        if ((q in pane) && agent[k] > hot[a[1], pane[q]]) hot[a[1], pane[q]] = agent[k]
        q = par[q]
      }
    }
    # a tmux client showing such a session stands in for the agent process
    for (c in client) for (n in kinds)
      if (((n, client[c]) in hot) && hot[n, client[c]] > agent[n, c]) agent[n, c] = hot[n, client[c]]
    for (k in agent) {
      split(k, a, SUBSEP); q = par[a[2]]
      for (i = 0; i < 10 && q > 1; i++) { if (agent[k] > anc[a[1], q]) anc[a[1], q] = agent[k]; q = par[q] }
    }
    done = 1
  }
  $1 == "Window" { w = $2 }
  $1 == "pid:" {
    win[$2] = 1
    if (("claude", $2) in anc) print "window", w, name[anc["claude", $2]]
    if (("hermes", $2) in anc) print "hermes", w, name[anc["hermes", $2]]
    p = program($2)
    if (p != "") print "prog", w, p
  }
  # Hermes hooks outside any window or tmux pane, such as in the background
  # gateway of the desktop app, make up the state of Hermes as a whole.
  END {
    app = 1
    for (p in hook) {
      q = p
      for (i = 0; i < 20 && q > 1 && !(q in win) && !(q in pane); i++) q = par[q]
      if (!(q in win) && !(q in pane) && st["hermes", p] > app) app = st["hermes", p]
    }
    print "app hermes", name[app]
  }
'
