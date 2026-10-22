#!/bin/sh
# Print the Hyprland address (no 0x) of every window with a `claude` process
# under it. Claude Code inside tmux counts for the terminals attached to that
# tmux session. Workspaces.qml decides which of these windows are terminals.
{
  ps -eo pid=,ppid=,comm= | sed 's/^/P /'
  tmux list-panes -a -F 'T #{pane_pid} #{session_id}' 2>/dev/null
  tmux list-clients -F 'C #{client_pid} #{session_id}' 2>/dev/null
  hyprctl clients
} | awk '
  $1 == "P" { par[$2] = $3; if ($4 == "claude") claude[$2] = 1; next }
  $1 == "T" { pane[$2] = $3; next }
  $1 == "C" { client[$2] = $3; next }
  !done {
    # tmux sessions with Claude Code in one of their panes
    for (p in claude) {
      q = p
      for (i = 0; i < 20 && q > 1; i++) { if (q in pane) hot[pane[q]] = 1; q = par[q] }
    }
    # a tmux client showing such a session stands in for the claude process
    for (c in client) if (client[c] in hot) claude[c] = 1
    for (p in claude) {
      q = par[p]
      for (i = 0; i < 10 && q > 1; i++) { anc[q] = 1; q = par[q] }
    }
    done = 1
  }
  $1 == "Window" { w = $2 }
  $1 == "pid:" && ($2 in anc) { print w }
'
