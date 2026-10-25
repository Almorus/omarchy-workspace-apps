# Workspace Apps

An [Omarchy](https://omarchy.org/) bar widget that shows which apps are open on each workspace, so you never lose track of a window again.

![Workspace Apps in the Omarchy bar](preview.png)

- **App icons per workspace.** Each workspace number is followed by small icons of the windows open on it. Omarchy web apps get the icon of their launcher.
- **Scratchpad group.** Windows parked with `Super + S` show up under an **S** at the end, so they're never out of sight. The group hides itself when the scratchpad is empty.
- **Current workspace in your theme's accent colour.** The number stays readable instead of being replaced by a glyph, and the colour follows your theme.
- **Claude Code gets its mascot.** Terminals running [Claude Code](https://claude.com/claude-code) show the little Claude Code guy instead of a terminal icon, also when Claude Code runs inside tmux. With the [optional hooks](#claude-code-status) it also shows what Claude Code is doing: it types on a keyboard while working, waves when it needs your input, and stands still when it's idle.
- **Workspaces past 10.** Workspaces 1–5 are always shown, and any other workspace in use appears too, including 11 and up.

Click a workspace number to switch to it, or click an app icon to jump straight to that window. For scratchpad icons it opens the scratchpad first. Hover an icon to see the window title, and click **S** to toggle the scratchpad.

## Install

```bash
omarchy plugin add https://github.com/Almorus/omarchy-workspace-apps
omarchy plugin enable almorus.workspace-apps --after omarchy.workspaces
omarchy plugin disable omarchy.workspaces
```

This puts the widget where the stock workspace numbers were and turns the stock ones off.

To go back:

```bash
omarchy plugin enable omarchy.workspaces --after almorus.workspace-apps
omarchy plugin disable almorus.workspace-apps
```

Update with `omarchy plugin update almorus.workspace-apps`.

If the bar doesn't pick up a change, run `omarchy restart shell`.

## Claude Code status

![The Claude Code mascot idle, typing while Claude Code works, and waving when it needs you](claude-status.gif)

The mascot can show what each Claude Code session is doing, so you can see from any workspace which session is busy and which one is waiting for you. Claude Code reports that through [hooks](https://docs.claude.com/en/docs/claude-code/hooks), so add these to the `hooks` section of `~/.claude/settings.json` (create the section if it's missing):

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" working" }] }],
  "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" working" }] }],
  "PostToolUseFailure": [{ "matcher": "*", "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" working" }] }],
  "PreToolUse": [{ "matcher": "AskUserQuestion|ExitPlanMode", "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" input" }] }],
  "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" input" }] }],
  "Notification": [{ "matcher": "permission_prompt|elicitation_dialog", "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" input" }] }],
  "Stop": [{ "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" idle" }] }],
  "StopFailure": [{ "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" idle" }] }],
  "SessionStart": [{ "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" idle" }] }],
  "SessionEnd": [{ "hooks": [{ "type": "command", "timeout": 5, "command": "f=\"$HOME/.config/omarchy/plugins/almorus.workspace-apps/claude-status.sh\"; [ ! -f \"$f\" ] || sh \"$f\" idle" }] }]
}
```

| The mascot… | when Claude Code… |
|---|---|
| types on a keyboard | works on your message or runs a tool |
| raises its hand and waves | asks for permission, asks you a question, or wants a plan approved |
| stands still | has finished, was interrupted, or hasn't started |

Each hook checks that the script is there first, so removing the plugin leaves them doing nothing. Open Claude Code sessions may need a restart to pick the hooks up. If one terminal has several sessions (tmux), the most urgent one wins: waving, then typing. The status needs `jq`, which Omarchy ships.

## How it works

- Workspaces and their windows come from Quickshell's Hyprland integration, the same data the stock widget uses.
- Icons are looked up from your installed desktop entries and icon theme. Apps whose window class doesn't match their desktop entry (Hermes reports `com.nousresearch.hermes`, but its entry is `hermes-desktop`) are matched by the last part of the class against each entry's id, `StartupWMClass`, program and name, exactly and ignoring case. A window without a matching desktop entry gets a generic app icon.
- Claude Code runs inside an ordinary terminal, so `claude-scan.sh` checks which windows have a `claude` process under them. For Claude Code inside tmux, it finds the terminal attached to that tmux session. It rechecks when windows open or close, and every 5 seconds. That's one `ps` and one `hyprctl clients` call, plus two quick `tmux` calls if tmux is installed.
- Only terminal windows (foot, Alacritty, kitty, Ghostty, WezTerm) get the mascot, so apps that start Claude Code themselves, such as Claude Desktop or an editor, keep their own icon.
- The hooks run `claude-status.sh`, which writes one line per session to `$XDG_RUNTIME_DIR/claude-status/<pid>` (in memory, gone after a reboot) and only when the state actually changes. It never prints anything and always exits successfully, so it can't block Claude Code. The widget watches that folder and rescans within about half a second. Files left by sessions that crashed are removed on the next scan.
- Pressing Esc in Claude Code runs no hook, so the scan also checks the end of a working session's transcript: if it was interrupted, the mascot goes back to idle within 5 seconds.
- The animation timer only runs while some session is working or waiting.
- Workspaces are updated in place, so switching workspaces or opening a window doesn't redraw the whole widget or close an open tooltip.
- The scratchpad is Omarchy's default `special:scratchpad`.

## License

MIT. The Claude Code mascot icon is a pixel-art drawing of the character shown in Claude Code's welcome screen; Claude and Claude Code are trademarks of Anthropic.
