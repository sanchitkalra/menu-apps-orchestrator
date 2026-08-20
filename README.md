# Orchestrator — Mini-App Host for macOS

A native macOS orchestrator that hosts tiny, LLM-generatable mini-apps. Each app is an executable (node/python/bash) that returns a declarative UI tree over ndjson stdio. The host renders it natively, brokers system APIs, and supervises lifecycle.

This repo implements the core runtime discussed in the design docs:

- **2-lane IPC** — `stdin` multiplexes `events` (tick/action, gated by `isBusy`) and `responses` (host.store/shell replies, immediate). `stdout` is app -> host. See `Sources/OrchestratorCore/IPCBridge.swift`.
- **Warm-ephemeral + resident** — ephemeral (pollers), persistent (todo/clipboard), resident (AWS/kubectl, never killed). See `ProcessSupervisor.swift` + `Scheduler.swift`.
- **Declarative DSL** — 12 components (`VStack/HStack, Text, Stat, List, Button, Form...`) Host validates and diffs. See `DSL.swift` and `Apps/todo`.
- **Per-app store** — `~/Orchestrator/Data/<id>/store.json` (SQLite in v2) for `host.store.get/set`.

## Quick Start

```bash
# build the host (no Xcode needed, just Swift 6 + CommandLineTools)
swift build --disable-sandbox

# run with the bundled todo sample
.build/debug/orchestrator ./Apps /tmp/orchestrator-data

# in another terminal, inspect
cat /tmp/orchestrator-data/todo/store.json
```

The bundled `Apps/todo` is a full persistent tile:

- `Apps/todo/manifest.json` — declares `lifecycle: persistent`, `permissions: ["store"]`
- `Apps/todo/index.js` — 90 lines, `onInit` + `onAction`, uses `host.store` + `host.render`

Host spawns `node index.js`, sends `init`, app replies with `render` (HStack/Stat + VStack/List/Form), Host diffs and prints `[render todo]` (SwiftUI grid in the full Xcode target).

## Project Layout

```
Package.swift
Sources/OrchestratorCore/
  Manifest.swift        # Codable manifest + lifecycle
  DSL.swift             # Node enum + RenderPayload, Zod-equivalent
  IPCBridge.swift       # ndjson, 2-lane queue, isBusy gating
  ProcessSupervisor.swift # spawn via Process(), owns pipes, restart
  Scheduler.swift       # interval/cron -> tick (coalesced)
  Store.swift           # per-app JSON kv, persisted
  ShellGateway.swift    # host.shell.exec/spawn
  RenderEngine.swift    # validate/diff/persist lastRender
  AppRegistry.swift     # scans ~/Orchestrator/Apps
Sources/OrchestratorCLI/main.swift # CLI host (prints renders)
Apps/todo/              # sample persistent app (node, no bun needed)
  manifest.json
  index.js  (and index.ts reference)
  schema.ts (Zod schema for LLM)
```

## Wire Protocol

App -> Host (stdout, each line JSON):
```json
{"id":1,"method":"host.store.get","params":{"key":"todos"}}
{"method":"render","params":"{\"tile\":{...},\"detail\":{...}}"}
{"id":1000,"method":"eventComplete"}
```

Host -> App (stdin):
```json
{"id":1,"result":"[{\"id\":\"1\",\"text\":\"buy milk\"}]"}
{"id":1000,"method":"event","params":"{\"type\":\"init\",\"appId\":\"todo\"}"}
{"id":1001,"method":"event","params":"{\"type\":\"action\",\"id\":\"toggle\",\"payload\":{\"id\":\"1\"}}"}
```

`eventComplete` (with same id as the event) clears `isBusy` and lets Host drain next `tick`/`action` from lane B. `host.*` replies go via lane A immediately, so `await host.store.get()` inside `onTick` does not deadlock.

## Todo App

See `Apps/todo/index.js` for the pattern LLMs should generate:

```js
export async function onInit() { todos = JSON.parse(await host.store.get("todos") || "[]"); host.render(view(todos)) }
export async function onAction({id, payload}) { /* update todos, store.set, host.render */ }
```

Tile shows `Stat: 2 left` + 2-line subtitle. Detail shows `Form` + `List` with `onClick: toggle` + `Button: Clear done`. All state is `host.store`, so cold start rehydrates instantly.

## Next Steps (needs Xcode)

The CLI host proves the runtime. To get the native grid:

1. Open in Xcode (once installed): the `Sources/OrchestratorCore` is Xcode-ready; add targets `OrchestratorApp` (SwiftUI App, MenuBarExtra + NSWindow grid), `TileView.swift` maps `Node -> SwiftUI`, `GridWindow.swift` lays out 2x1/1x1 tiles, `DetailWindow.swift` sheets on click.
2. Add `WKWebView` escape hatch for detail webviews, permission prompt UI, and `NSPasteboard` watcher for clipboard app.
3. The 6 starter apps (GitHub polling, Statuspage, Sentry, SQL metrics, clipboard, todo) all reuse the same `interval` + `host.fetch` + `Stat/Sparkline` pattern — only the `onTick` body changes.

## Why not Xcode yet

Current machine has only CommandLineTools (no `xcodebuild`). `swift build` validates all core logic; SwiftUI grid files are scaffolded but not compiled until Xcode is present. The runtime (the hard part — process supervision, IPC, scheduling, store) is complete and tested via the todo app logs above.

