# AGENTS · blogTrack working notes

Conventions for any future agent (Claude or otherwise) working on this
repo. Short on purpose.

## Layout

```
blogTrack/
├── scripts/                # cron + toggle (bash)
├── vscode-extension/       # local-only VS Code extension
└── .devlog-state/          # gitignored: snapshots + cron log
```

## Bumping the VS Code extension

Local-install path is `~/.vscode/extensions/<publisher>.<name>-<version>/`.
VS Code parses the version from the folder name, so changing
`package.json`'s version field alone isn't enough — the install folder
(or symlink) has to be renamed to match.

Use the helper:

```bash
./vscode-extension/bump.sh         # patch bump (default)
./vscode-extension/bump.sh minor   # 0.1.x → 0.2.0
./vscode-extension/bump.sh major   # 0.x.y → 1.0.0
```

What it does, in order:

1. Reads `vscode-extension/package.json` for the current version.
2. Computes the next version at the requested level.
3. Writes the new version into `package.json`.
4. Renames the symlink at `~/.vscode/extensions/nate-local.track4blog-<old>`
   to `…-<new>` (creates a fresh symlink if there wasn't one).
5. Prints the reload step.

After running, reload VS Code so the new install registers:

```
Cmd+Shift+P → Developer: Reload Window
```

(Quitting and reopening VS Code works too.)

## When to bump

- **patch** — bug fix or behavior tweak in the extension code with no
  new commands or settings.
- **minor** — added a new command, menu binding, or setting.
- **major** — backward-incompatible change to a setting key, command
  ID, or shell-script CLI surface that the extension depends on.

## Cron / shell-script changes

No version field. Just commit and push. `devlog-cron.sh` reloads its
config on every run, so changes take effect on the next scheduled
invocation (or the next manual run).

If you change the config schema (`devlog-config.json`), update both
`scripts/track4blog.sh` (which writes new entries) and
`scripts/devlog-cron.sh` (which reads them) in the same commit.

## State

`.devlog-state/` lives at the repo root and is gitignored. Inside:

- `<key>.last` — last-seen contents of each watched file. Snapshots
  advance only after a successful Claude run; failures keep the
  snapshot in place so the next cron run retries the same diff.
- `cron.log` — append-only log of every cron invocation. First place
  to look when "why didn't a post show up" comes up.

Wiping state is safe: the next cron run treats every watch as fresh,
takes a baseline snapshot, and won't post until the next batch of
changes accumulates past `threshold_chars`.

## Testing without waiting

```bash
# Run the cron by hand
./scripts/devlog-cron.sh

# Tail the log
tail -f .devlog-state/cron.log
```

To force a particular watch back to "fresh" (treat current content as
the baseline, no post until next batch):

```bash
KEY=$(printf '%s' "/abs/path/to/your/file.md" | shasum | cut -c1-16)
rm .devlog-state/$KEY.last
```

## Don't

- Don't commit `.devlog-state/`. It's user-local.
- Don't hardcode a destination repo path inside scripts. Read it from
  `devlog-config.json`'s `site_repo` (set via `track4blog.sh
  --set-destination`).
- Don't change the `<publisher>.<name>` portion of the extension
  install folder name without also updating `bump.sh` to match — the
  prefix is what locates the existing install for renaming.
