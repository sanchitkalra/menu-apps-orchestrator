# Orchestrator — Xcode Build & Test Guide

This guide is for an agent (or human) on a **macOS machine with Xcode 15+** to build, run, and verify the Orchestrator menu-bar host and its mini-apps.

## 1. Prerequisites

- macOS 14+ (Sonoma or later)
- Xcode 15+ with Command Line Tools: `xcode-select --install`
- Node 18+ (`node --version`) — mini-apps are `node` executables
- No `bun` required (all samples use `node index.js`)

Verify:

```bash
xcodebuild -version   # Xcode 15.x
swift --version       # Apple Swift 6.x
node --version        # v18+
```

## 2. Clone and SwiftPM sanity check (no Xcode needed)

```bash
git clone <repo-url> menu-apps
cd menu-apps
swift build --disable-sandbox   # validates OrchestratorCore + CLI
# should end with "Build complete!"

# Run CLI host headless (proves IPC + lifecycle without UI)
swift build --disable-sandbox
.build/debug/orchestrator ./Apps /tmp/orchestrator-data &
sleep 5; cat /tmp/orchestrator-data/todo/lastRender.json | python3 -m json.tool | head -n 30
# expect: tile with "2 left" and detail with Form/List
pkill -f "orchestrator.*Apps"
```

If this fails, stop — core is broken, don't open Xcode.

## 3. Open in Xcode

The repo is a SwiftPM package with an `OrchestratorApp` target for the menu-bar UI (stubs under `Sources/OrchestratorApp/` that only compile with `canImport(SwiftUI)`).

1. Open `Package.swift` in Xcode: `open Package.swift` or `xed .`
2. Xcode will resolve the package (no external dependencies).
3. Select scheme **OrchestratorApp** (not `orchestrator` CLI) and a My Mac destination.
4. Edit scheme → Run → Options → ensure `LSUIElement` is respected (no Dock icon expected).

Build:

```bash
xcodebuild -scheme OrchestratorApp -configuration Debug build
# or inside Xcode: Product → Build (⌘B)
```

Expected: `TileView.swift` and `GridWindow.swift` compile without errors. Warnings about `SwiftShims` are benign.

## 4. Run the menu-bar app

In Xcode: Product → Run (⌘R). You should see:

- A `square.grid.2x2` icon appear in the menu bar (right side)
- Click it → a window-style panel (680×420) with a grid of tiles:
  - **Todos** (wide, 2 left) — from `Apps/todo` (persistent)
  - **GitHub** (zen) — from `Apps/github` (ephemeral, interval 5m, uses `host.fetch`)
  - **Sentry** (2 new) — `Apps/sentry`
  - **Clipboard** (3) — `Apps/clipboard` (persistent, polls `pbpaste`)
  - **SQL** (p95) — `Apps/sql` (sparkline)

Click a tile → detail sheet appears (same DSL, no WebView). For Todos, try Add / toggle (○→✓) / Clear done — tile updates instantly via `host.render` diff.

If the panel is empty, check Console → filter `render` — host prints `[render <id>]` on every `host.render`. No print means IPC failed; check `Apps/<id>/manifest.json` has `"enabled": true` and `entrypoint: "node index.js"`.

## 5. Verify core behaviors

### IPC + lifecycle
```bash
# Terminal 1: run host with file logging
.build/debug/OrchestratorApp 2>&1 | tee /tmp/orchestrator.log &
# or CLI:
.build/debug/orchestrator ./Apps /tmp/orchestrator-data > /tmp/orchestrator.log 2>&1 &

# Trigger a tick manually (if you add a debug menu) or wait for interval
# For Todo (persistent, 30s reaper): check it stays alive >10s, then idle 30s it is reaped
sleep 7; pgrep -f "node.*todo" || ps aux | grep "node index.js" | grep -v grep
# should still be alive at 7s (persistent), gone after 35s
```

### Store + lastRender
```bash
cat ~/Orchestrator/Data/todo/store.json      # {"todos":"[...]"}
cat ~/Orchestrator/Data/todo/lastRender.json | python3 -m json.tool | head -n 30
# after kill and restart, tile shows lastRender immediately before re-spawn (cold start)
```

### Permissions
Edit `Apps/github/manifest.json` → remove `"fetch"` from `permissions`, restart host, check log:
```
[perm] denied github host.fetch: ...
```
Tile will show red error. Restore permission and restart.

### FileWatcher hot-reload
```bash
echo '{"id":"todo","name":"Todos","version":"0.1.1","entrypoint":"node index.js","lifecycle":"persistent","tile":{"size":"2x1"},"permissions":["store"],"enabled":false}' > Apps/todo/manifest.json
# within 2s, host logs: [watcher] removed/disabled todo -> terminating
# tile disappears
```

## 6. Run the web preview (no Xcode)

If Xcode is unavailable, the same DSL renders in the browser:

```bash
open web-preview/index.html
# or
python3 -m http.server 8000 --directory web-preview
# open http://localhost:8000
```

This is the reference rendering for `TileView` — pixel-identical to SwiftUI.

## 7. Mini-app contract (for LLM)

Each app is `Apps/<id>/manifest.json` + `index.js`:

```json
{
  "id": "my-app",
  "entrypoint": "node index.js",
  "lifecycle": "ephemeral|persistent|resident",
  "schedule": {"interval":"5m"} ,
  "permissions": ["store","fetch","notify","shell.exec"]
}
```

`index.js` must export `onInit`/`onTick`/`onAction` via stdin `event` handling and call `host.render({tile, detail})` where tile/detail are DSL Nodes (see `Sources/OrchestratorCore/DSL.swift` or `web-preview/index.html` `elForNode`). Use `bin/orchestrator create my-app --template poller` to scaffold.

## 8. Known v1 limitations

- `host.notify` only logs in CLI; `UNUserNotificationCenter` enabled only when running as `.app` bundle
- `host.fetch` is simple GET, no ETag/headers (GitHub zen works unauthenticated; add `github_token` via `host.secrets` for real notifications in v2)
- `Store` is JSON file per app (SQLite in v2), `host.shell.spawn` streaming is not yet forwarded as `shell.output` events
- Cron `0 9 * * *` works via `Scheduler.nextCronDate`, but `system.wake` coalescing is stubbed

## 9. Troubleshooting

- `xcodebuild: requires Xcode` → install from App Store, `sudo xcode-select --switch /Applications/Xcode.app`
- `SwiftShims` pcm error under sandbox → use `swift build --disable-sandbox` or run inside Xcode (Xcode disables sandbox)
- `BundleProxy nil` crash on notify → you are running CLI, not `.app` — expected, notify just logs

Contact: file an issue with `/tmp/orchestrator.log` and `~/Orchestrator/Data/<id>/store.json`.
