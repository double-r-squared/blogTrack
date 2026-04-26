# track4blog · VS Code extension

Two commands surfaced via right-click and the command palette:

- **track4blog: Toggle Tracking** — adds or removes the selected file
  from the cron's watch list. Bound to the Explorer right-click menu,
  the editor-tab right-click menu, and the in-editor right-click menu.
- **track4blog: Set Destination** — sets the destination blog repo that
  the cron publishes generated posts into. Run once during setup.
  Command palette only (no menu binding).

Both commands call `scripts/track4blog.sh` in the blogTrack repo,
which manages `scripts/devlog-config.json`. The cron reads that
config on its next run.

## Install (local, no publishing)

VS Code reads extensions from `~/.vscode/extensions/<id>/`. Symlink
the extension folder there:

```bash
ln -s "$HOME/blogTrack/vscode-extension" "$HOME/.vscode/extensions/nate-local.track4blog-0.1.0"
```

Quit and reopen VS Code. Both commands should appear in the command
palette (`⌘⇧P` → "track4blog"), and **Toggle Tracking** should appear
when you right-click any file.

To upgrade later: bump the version in `package.json`, rename the
symlink target to match (or just delete and re-link).

## Configure the script path

By default the extension expects the shell script at
`~/blogTrack/scripts/track4blog.sh`. If your blogTrack checkout lives
somewhere else, override in user settings:

```jsonc
// settings.json
"track4blog.scriptPath": "/absolute/path/to/blogTrack/scripts/track4blog.sh"
```

## First-time setup flow

1. **Set the destination**: command palette → **track4blog: Set
   Destination** → enter the absolute path of your blog repo. Confirms
   with a status-bar message.
2. **Track your first source**: right-click a markdown file (e.g.
   `~/some-project/timeline.md`) → **track4blog: Toggle Tracking**. A
   status-bar message and macOS notification confirm the toggle.
3. The cron picks both up on its next run.

## Why an extension and not a Finder Quick Action

Quick Actions live in Finder's right-click menu, which doesn't help
when you're already in VS Code editing a timeline. The extension
surfaces the toggle in the editor itself — same place you're already
looking when you decide a file is worth tracking.
