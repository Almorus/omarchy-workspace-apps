# Workspace Apps

An [Omarchy](https://omarchy.org/) bar widget that shows which apps are open on each workspace, so you never lose track of a window again.

![Workspace Apps in the Omarchy bar](preview.png)

- **App icons per workspace.** Each workspace number is followed by small icons of the windows open on it. Omarchy web apps get the icon of their launcher.
- **Scratchpad group.** Windows parked with `Super + S` show up under an **S** at the end, so they're never out of sight. The group hides itself when the scratchpad is empty.
- **Current workspace in your theme's accent colour.** The number stays readable instead of being replaced by a glyph, and the colour follows your theme.
- **Claude Code gets its mascot.** Terminals running [Claude Code](https://claude.com/claude-code) show the little Claude Code guy instead of a terminal icon, also when Claude Code runs inside tmux.
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

## How it works

- Workspaces and their windows come from Quickshell's Hyprland integration, the same data the stock widget uses.
- Icons are looked up from your installed desktop entries and icon theme. A window without a matching desktop entry gets a generic app icon.
- Claude Code runs inside an ordinary terminal, so `claude-scan.sh` checks which windows have a `claude` process under them. For Claude Code inside tmux, it finds the terminal attached to that tmux session. It rechecks when windows open or close, and every 5 seconds. That's one `ps` and one `hyprctl clients` call, plus two quick `tmux` calls if tmux is installed.
- Only terminal windows (foot, Alacritty, kitty, Ghostty, WezTerm) get the mascot, so apps that start Claude Code themselves, such as Claude Desktop or an editor, keep their own icon.
- Workspaces are updated in place, so switching workspaces or opening a window doesn't redraw the whole widget or close an open tooltip.
- The scratchpad is Omarchy's default `special:scratchpad`.

## License

MIT. The Claude Code mascot icon is a pixel-art drawing of the character shown in Claude Code's welcome screen; Claude and Claude Code are trademarks of Anthropic.
