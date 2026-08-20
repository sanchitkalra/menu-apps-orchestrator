import Foundation
import OrchestratorCore

let fm = FileManager.default
let home = FileManager.default.homeDirectoryForCurrentUser
let appsRoot: URL
let dataRoot: URL
if CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-") {
    appsRoot = URL(fileURLWithPath: CommandLine.arguments[1])
    dataRoot = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\(home.path)/Orchestrator/Data")
} else {
    appsRoot = URL(fileURLWithPath: "\(home.path)/Orchestrator/Apps")
    dataRoot = URL(fileURLWithPath: "\(home.path)/Orchestrator/Data")
}

try? fm.createDirectory(at: appsRoot, withIntermediateDirectories: true)
try? fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)

print("Orchestrator starting")
print("Apps: \(appsRoot.path)")
print("Data: \(dataRoot.path)")

let permissions = PermissionManager()
let store = Store(root: dataRoot)
let shell = ShellGateway()
let supervisor = ProcessSupervisor(store: store, shell: shell, permissions: permissions) { appId, payload in
    // In CLI mode, pretty-print renders
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let tile = payload.tile, let data = try? encoder.encode(tile), let s = String(data: data, encoding: .utf8) {
        print("\n[render \(appId)] tile:\n\(s)")
    }
    if let detail = payload.detail, let data = try? encoder.encode(detail), let s = String(data: data, encoding: .utf8) {
        print("[render \(appId)] detail:\n\(s)\n")
    }
}

let scheduler = Scheduler { appId in
    Task { await supervisor.sendTick(appId: appId) }
}
let fileWatcher = FileWatcher(appsRoot: appsRoot)
var knownIds: Set<String> = []

Task {
    let manifests = (try? await registryScan()) ?? []
    print("Found \(manifests.count) apps")
    for m in manifests {
        await supervisor.register(manifest: m)
        knownIds.insert(m.id)
        print(" - \(m.id) (\(m.lifecycle.rawValue)) entry:\(m.entrypoint)")
        try? await supervisor.spawn(appId: m.id, appsRoot: appsRoot, dataRoot: dataRoot)
        await scheduler.register(appId: m.id, schedule: m.schedule)
        if m.lifecycle == .resident {
            print("  -> resident, keeping alive")
        }
    }
    if manifests.isEmpty {
        print("No apps found. Create one at \(appsRoot.path)/todo/manifest.json")
        print("Run: mkdir -p \(appsRoot.path) && cp -r \(FileManager.default.currentDirectoryPath)/Apps/todo \(appsRoot.path)/")
    }
    // start hot-reload watcher (polls every 2s)
    await fileWatcher.start { newManifests in
        Task {
            let newIds = Set(newManifests.map { $0.id })
            let removed = knownIds.subtracting(newIds)
            let added = newIds.subtracting(knownIds)
            for id in removed {
                print("[watcher] removed/disabled \(id) -> terminating")
                await scheduler.cancel(appId: id)
                await supervisor.terminate(appId: id)
                knownIds.remove(id)
            }
            for m in newManifests where added.contains(m.id) {
                print("[watcher] added \(m.id) -> spawning")
                await supervisor.register(manifest: m)
                knownIds.insert(m.id)
                try? await supervisor.spawn(appId: m.id, appsRoot: appsRoot, dataRoot: dataRoot)
                await scheduler.register(appId: m.id, schedule: m.schedule)
            }
            // updated manifests (same id, new version/entrypoint) -> restart
            for m in newManifests where !added.contains(m.id) {
                // naive: restart if hash changed (watcher already diffed)
                // for v1, just re-register schedule
                await scheduler.register(appId: m.id, schedule: m.schedule)
            }
        }
    }
}

func registryScan() async throws -> [Manifest] {
    let registry = AppRegistry(appsRoot: appsRoot)
    return try await registry.scan()
}

RunLoop.main.run()
