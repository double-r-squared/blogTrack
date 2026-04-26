# scripts · the cron + the toggle

Three files do the work:

| File | Role |
| --- | --- |
| `track4blog.sh` | Manage `devlog-config.json`. Toggles a file's presence in `watches[]`, or sets the global `site_repo` destination via `--set-destination`. Called by the VS Code extension. |
| `devlog-config.json` | Source of truth: one `site_repo` (destination), many `watches[]` (sources). |
| `devlog-cron.sh` | Runs from cron / launchd. Diffs each watched file against its last snapshot. Invokes Claude only when the diff exceeds the per-watch character threshold. |

`devlog-prompt.txt` is the prompt template the cron sends to Claude.

## Token-frugal by design

Claude is *only* invoked when a watched file's accumulated diff against
its last snapshot crosses `threshold_chars` (default 800). Below that
threshold the cron exits silently after a few `shasum` calls and a
`diff`. No LLM calls, no token spend. The snapshot only advances on a
successful Claude run; failures leave it in place so the next cron run
retries the same diff.

## Setup

### 1. Tooling

```bash
brew install jq
```

`claude` (the Claude Code CLI) must be on `PATH`. Cron's default `PATH`
is usually narrow; set it explicitly at the top of your crontab.

### 2. Install the VS Code extension

See [`../vscode-extension/README.md`](../vscode-extension/README.md).
Symlink the folder into `~/.vscode/extensions/`, restart VS Code.

### 3. Set the destination blog repo

Either via the extension (command palette → **track4blog: Set
Destination** → absolute path), or directly:

```bash
./scripts/track4blog.sh --set-destination /absolute/path/to/your/blog-repo
```

This writes the path into `devlog-config.json`'s top-level `site_repo`
field. One destination per blogTrack install; many sources publish into
it.

### 4. Add the cron entry

```cron
# Run every day at 11:30 PM
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
30 23 * * * /Users/you/blogTrack/scripts/devlog-cron.sh
```

Adjust the path to `claude` in the `PATH=` line if it lives elsewhere
(`which claude` to check).

### 5. Track your first source

In VS Code, right-click a markdown file (e.g. `~/some-project/timeline.md`)
→ **track4blog: Toggle Tracking**. A status-bar message and macOS
notification confirm.

The first cron run after tracking just snapshots the file — no post
yet. Subsequent runs compute the diff against that snapshot and post
once the diff passes the threshold.

## Config schema

```jsonc
{
  // One destination per blogTrack install. Set via track4blog --set-destination
  // (or the VS Code "Set Destination" command).
  "site_repo": "/Users/you/path/to/blog-repo",

  // Many sources. Each is a markdown file that the cron diffs and that
  // publishes into the destination above.
  "watches": [
    {
      "path": "/Users/you/path/to/some-project/timeline.md",
      "series": "Some Project development log",
      "slug_prefix": "some-project-devlog",
      "title_prefix": "Some Project development log",
      "threshold_chars": 800,
      "tags": ["devlog", "some-project"]
    }
  ]
}
```

Field meanings:

- **`series`** — the human-readable name passed to Claude in the prompt.
- **`slug_prefix`** — generated post slug becomes `<slug_prefix>-<YYYY-MM-DD>`.
- **`title_prefix`** — generated post title becomes `<title_prefix> · <YYYY-MM-DD>`.
- **`threshold_chars`** — minimum new-content length (in characters) to
  trigger a post. Higher = fewer, beefier posts. 800 ≈ a couple of
  short timeline entries; 2000 ≈ a sizeable batch.
- **`tags`** — propagated to the destination repo's blog post registry.

`track4blog.sh` adds entries with these defaults derived from the file's
parent directory name. Edit them after the first add if the auto-naming
is off.

## Testing without waiting

Force a post for a watched file right now:

```bash
# 1. Make sure the file has at least threshold_chars of new content
#    relative to its current snapshot.

# 2. Run the cron script by hand:
./scripts/devlog-cron.sh

# 3. Tail the log:
tail -f ../.devlog-state/cron.log
```

Reset a watch (treat the current state of the file as a new baseline,
no post):

```bash
KEY=$(printf '%s' "/abs/path/to/your/file.md" | shasum | cut -c1-16)
rm ../.devlog-state/$KEY.last
```

The next cron run snapshots the file fresh and won't post until the
next threshold-sized batch of changes lands.

## State

`.devlog-state/` at the blogTrack repo root (gitignored) holds:

- `<key>.last` — last seen contents of each watched file. Diffs are
  computed against this. Advances only after a successful Claude run.
- `cron.log` — append-only log of every cron invocation. Useful when
  debugging "why didn't a post show up" questions.
