import Foundation

public actor ShellGateway {
    private var spawned: [Int32: Process] = [:]
    public init() {}
    public struct Spawned: Codable, Sendable { public var pid: Int32; public var command: String }

    // host.shell.exec - one-shot, returns stdout
    public func exec(command: String, timeoutSeconds: Double = 10) async -> (stdout: String, stderr: String, exitCode: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return ("", "\(error)", -1) }
        // timeout
        let result = await withTaskGroup(of: Int32.self) { group -> Int32 in
            group.addTask { p.waitUntilExit(); return p.terminationStatus }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1e9)); if p.isRunning { p.terminate() }; return -1 }
            return await group.next() ?? -1
        }
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, result)
    }

    // host.shell.spawn - long-lived, streams output via callback, tracked for cleanup
    public func spawn(command: String, onOutput: @escaping (String) -> Void) async -> Spawned? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        let out = Pipe()
        p.standardOutput = out; p.standardError = out
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if let s = String(data: d, encoding: .utf8), !s.isEmpty { onOutput(s) }
        }
        do { try p.run() } catch { return nil }
        let pid = p.processIdentifier
        spawned[pid] = p
        p.terminationHandler = { [weak self] _ in Task { await self?.remove(pid: pid) } }
        return Spawned(pid: pid, command: command)
    }

    private func remove(pid: Int32) { spawned.removeValue(forKey: pid) }

    public func kill(pid: Int32) {
        spawned[pid]?.terminate()
        spawned.removeValue(forKey: pid)
    }

    public func killAll() {
        for (_, p) in spawned { p.terminate() }
        spawned.removeAll()
    }
}
