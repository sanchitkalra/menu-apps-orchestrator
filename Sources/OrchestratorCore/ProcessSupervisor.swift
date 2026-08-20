import Foundation

public actor ProcessSupervisor {
    public struct Managed: Sendable {
        public var manifest: Manifest
        public var process: Process?
        public var bridge: IPCBridge
        public var restartAttempts: Int = 0
    }

    private var apps: [String: Managed] = [:]
    private var onRender: ((String, RenderPayload) -> Void)?
    private var store: Store
    private var shell: ShellGateway
    private var permissions: PermissionManager
    private var reaperTasks: [String: Task<Void, Never>] = [:]
    private var appsRoot: URL?
    private var dataRoot: URL?

    public init(store: Store, shell: ShellGateway, permissions: PermissionManager, onRender: ((String, RenderPayload) -> Void)? = nil) {
        self.store = store
        self.shell = shell
        self.permissions = permissions
        self.onRender = onRender
    }

    public func register(manifest: Manifest) {
        apps[manifest.id] = Managed(manifest: manifest, bridge: IPCBridge())
        Task { await permissions.register(manifest: manifest) }
    }

    public func spawn(appId: String, appsRoot: URL, dataRoot: URL) async throws {
        guard var managed = apps[appId] else { return }
        self.appsRoot = appsRoot
        self.dataRoot = dataRoot
        // cancel any pending reaper
        reaperTasks[appId]?.cancel()
        reaperTasks.removeValue(forKey: appId)
        let manifest = managed.manifest

        let appDir = appsRoot.appendingPathComponent(appId)
        let dataDir = dataRoot.appendingPathComponent(appId)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let process = Process()
        // entrypoint is shell-like: "bun run index.ts"
        let parts = manifest.entrypoint.split(separator: " ").map(String.init)
        guard let exe = parts.first else { return }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [exe] + parts.dropFirst()
        process.currentDirectoryURL = appDir
        var env = ProcessInfo.processInfo.environment
        env["ORCHESTRATOR_APP_ID"] = appId
        env["ORCHESTRATOR_DATA_DIR"] = dataDir.path
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let bridge = managed.bridge
        await bridge.attach(stdin: stdinPipe.fileHandleForWriting, appId: appId, store: store, shell: shell, permissions: permissions, onRender: { [weak self] payload in
            Task { await self?.handleRender(appId: appId, payload: payload) }
        }, onIdle: { [weak self] in
            Task { await self?.scheduleReaper(appId: appId) }
        })

        // stdout reader with buffering (Box to avoid Swift 6 captured-var warning)
        final class BufferBox: @unchecked Sendable { var value = "" }
        let stdoutBuffer = BufferBox()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            stdoutBuffer.value += str
            while let range = stdoutBuffer.value.range(of: "\n") {
                let line = String(stdoutBuffer.value[..<range.lowerBound])
                stdoutBuffer.value = String(stdoutBuffer.value[range.upperBound...])
                let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !l.isEmpty {
                    Task { await bridge.handleStdoutLine(l) }
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                print("[\(appId) stderr] \(s)", terminator: "")
            }
        }

        process.terminationHandler = { p in
            let code = p.terminationStatus
            print("[supervisor] \(appId) exited with \(code)")
            // restart logic for resident
            if manifest.lifecycle == .resident {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    try? await self.spawn(appId: appId, appsRoot: appsRoot, dataRoot: dataRoot)
                }
            }
        }

        try process.run()
        managed.process = process
        apps[appId] = managed

        // send init event (lane B, will set isBusy)
        let initMsg = WireMessage(id: 1000, method: "event", params: AnyCodable("{\"type\":\"init\",\"appId\":\"\(appId)\"}"))
        await bridge.sendEvent(initMsg)
    }

    private func handleRender(appId: String, payload: RenderPayload) async {
        onRender?(appId, payload)
        try? await store.saveLastRender(appId: appId, payload: payload)
        if let data = try? JSONEncoder().encode(payload), let s = String(data: data, encoding: .utf8) {
            fputs("[render \(appId)] \(s.prefix(500))\n", stderr)
        }
    }

    private func scheduleReaper(appId: String) {
        guard let manifest = apps[appId]?.manifest else { return }
        if manifest.lifecycle == .resident { return }
        let timeout: UInt64 = manifest.lifecycle == .ephemeral ? 5 : 30
        reaperTasks[appId]?.cancel()
        reaperTasks[appId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.reapIfIdle(appId: appId)
        }
    }

    private func reapIfIdle(appId: String) async {
        guard let managed = apps[appId], let proc = managed.process, proc.isRunning else { return }
        // only reap if bridge is idle (no pending laneB and not busy) - checked via onIdle already
        fputs("[supervisor] reaping \(appId) after idle\n", stderr)
        proc.terminate()
        // give 2s to exit gracefully, then kill
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if proc.isRunning { proc.terminate() }
        apps[appId]?.process = nil
    }

    private func cancelReaper(appId: String) {
        reaperTasks[appId]?.cancel()
        reaperTasks.removeValue(forKey: appId)
    }

    public func sendTick(appId: String) async {
        guard apps[appId] != nil else { return }
        cancelReaper(appId: appId)
        if !(apps[appId]?.process?.isRunning ?? false) {
            if let ar = appsRoot, let dr = dataRoot { try? await spawn(appId: appId, appsRoot: ar, dataRoot: dr); return }
        }
        guard let m = apps[appId] else { return }
        let msg = WireMessage(id: Int.random(in: 1001...99999), method: "event", params: AnyCodable("{\"type\":\"tick\"}"))
        await m.bridge.sendEvent(msg)
    }

    public func sendAction(appId: String, actionId: String, payload: [String:String]? = nil) async {
        guard apps[appId] != nil else { return }
        cancelReaper(appId: appId)
        if !(apps[appId]?.process?.isRunning ?? false) {
            if let ar = appsRoot, let dr = dataRoot { try? await spawn(appId: appId, appsRoot: ar, dataRoot: dr) }
            // after spawn, the action will be queued; init will run first, then action
        }
        guard let m = apps[appId] else { return }
        var p = "{\"type\":\"action\",\"id\":\"\(actionId)\""
        if let payload, let data = try? JSONSerialization.data(withJSONObject: payload), let s = String(data: data, encoding: .utf8) {
            p += ",\"payload\":\(s)"
        }
        p += "}"
        let msg = WireMessage(id: Int.random(in: 1001...99999), method: "event", params: AnyCodable(p))
        await m.bridge.sendEvent(msg)
    }

    public func terminate(appId: String) {
        apps[appId]?.process?.terminate()
    }
}
