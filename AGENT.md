# Agent Handoff — Orchestrator

This repo is a **macOS menu-bar orchestrator** that hosts LLM-generatable mini-apps (executables) via ndjson stdio. See `README.md` for product overview and `docs/XCODE_BUILD.md` for the exact Xcode build/test steps.

**For an agent on a machine with Xcode:**
1. Read `docs/XCODE_BUILD.md` end-to-end.
2. Run `swift build --disable-sandbox` first (core IPC/lifecycle sanity).
3. Open `Package.swift` in Xcode, build scheme `OrchestratorApp`, run (⌘R), verify menu-bar tiles and `lastRender.json`.
4. Use `bin/orchestrator create <id> --template poller` to scaffold new mini-apps from `Sources/OrchestratorCore/DSL.swift`.

**Sample apps fully implemented:** `Apps/todo` (persistent, store) and `Apps/github` (ephemeral poller, fetch/notify/secrets). Both are reference implementations for the DSL.

**Do not** run `host.notify` via `UNUserNotificationCenter` in CLI — it crashes without a bundle (guarded in `IPCBridge.swift`).
