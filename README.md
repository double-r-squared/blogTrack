# blogTrack

Watch markdown timeline files in your project repos for accumulated
changes. When a file's diff against its last snapshot crosses a length
threshold, invoke Claude to draft a new dev-log blog post in the
appropriate series of your blog repo, register it, build, commit, and
push.

Two pieces:

- **`scripts/`** — the cron job that runs periodically, plus the toggle
  script that updates the watch list.
- **`vscode-extension/`** — adds **track4blog: Toggle Tracking** to the
  Explorer / editor right-click menus so you don't have to edit the
  config JSON by hand.

## Token-frugal by design

Claude is *only* invoked when a watched file's accumulated diff against
its last snapshot crosses `threshold_chars` (default 800). Below that
threshold the cron exits silently after a few `shasum` calls and a
`diff`. No LLM calls, no token spend. The snapshot only advances on a
successful Claude run; failures leave the snapshot in place so the
next cron run retries the same diff.

## How it fits together

```
[ project repo ]                     [ blogTrack ]                       [ blog repo ]
 timeline.md  ─── watched by ───►   devlog-cron.sh  ─── invokes ───►   src/blog/content/<slug>.md
                                          │                                     ▲
                                          │                                     │
                                          │ reads               writes / commits│
                                          ▼                                     │
                                  devlog-config.json ──────────────►  posts.ts (registry)
                                          ▲
                                          │
                                          │ toggled by
                                          │
                                  track4blog.sh ◄──── VS Code right-click ───── you
```

## Setup

See [`scripts/README.md`](scripts/README.md) for the full walkthrough.
The short version:

1. `brew install jq` and make sure `claude` is on your PATH.
2. Open `scripts/devlog-config.json` and set `site_repo` to the
   absolute path of your blog repo.
3. Symlink `vscode-extension/` into `~/.vscode/extensions/` and restart
   VS Code.
4. Add a daily entry to `crontab -e` pointing at `scripts/devlog-cron.sh`.
5. Right-click any timeline file in VS Code → **track4blog: Toggle
   Tracking**. The cron picks it up on its next run.

## State

Local snapshots and the cron log live in `.devlog-state/` at the repo
root. Gitignored.
