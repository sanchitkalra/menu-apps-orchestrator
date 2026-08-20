import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Wire protocol (ndjson, JSON-RPC 2.0 subset)
public struct WireMessage: Codable, Sendable {
    public var id: Int?
    public var method: String?
    public var params: AnyCodable?
    public var result: AnyCodable?
    public var error: String?
    public init(id: Int? = nil, method: String? = nil, params: AnyCodable? = nil, result: AnyCodable? = nil, error: String? = nil) {
        self.id = id; self.method = method; self.params = params; self.result = result; self.error = error
    }
}

// Minimal AnyCodable for forwarding - stores raw JSON string
public struct AnyCodable: Codable, Sendable, Equatable {
    public var value: String
    public init(_ value: String) { self.value = value }
    // also allow init from dict
    public init(dict: [String: String]) {
        if let d = try? JSONSerialization.data(withJSONObject: dict), let s = String(data: d, encoding: .utf8) { self.value = s }
        else { self.value = "{}" }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = "\(i)" }
        else if let d = try? c.decode(Double.self) { value = "\(d)" }
        else if let b = try? c.decode(Bool.self) { value = "\(b)" }
        else if let dict = try? c.decode([String: String].self), let d = try? JSONSerialization.data(withJSONObject: dict), let s = String(data: d, encoding: .utf8) { value = s }
        else { value = "{}" }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        // try to emit raw JSON object if value looks like JSON
        if let data = value.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data), !(value.hasPrefix("\"")) {
            // re-emit as string for simplicity - receiver parses string
            try c.encode(value)
        } else {
            try c.encode(value)
        }
    }
    public func decodeDict() -> [String: String]? {
        guard let d = value.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return nil }
        return j
    }
}

// MARK: - IPCBridge with 2-lane queue
public actor IPCBridge {
    public enum Lane: Sendable { case response, event }
    public struct Queued: Sendable { var lane: Lane; var message: WireMessage; var priority: Int }

    private var isBusy: Bool = false
    private var laneB: [WireMessage] = [] // events (tick/action) gated
    private var stdinHandle: FileHandle?
    private var onRender: ((RenderPayload) -> Void)?
    private var onIdle: (() -> Void)?
    private var store: Store?
    private var shell: ShellGateway?
    private var permissions: PermissionManager?
    private var appId: String = ""

    public init() {}

    public func attach(stdin: FileHandle, appId: String, store: Store, shell: ShellGateway, permissions: PermissionManager, onRender: @escaping (RenderPayload) -> Void, onIdle: (() -> Void)? = nil) {
        self.stdinHandle = stdin
        self.appId = appId
        self.store = store
        self.shell = shell
        self.permissions = permissions
        self.onRender = onRender
        self.onIdle = onIdle
    }

    // Host -> App: enqueue event (tick/action) - gated by isBusy
    // Actions jump ahead of ticks; ticks coalesce (only one pending tick)
    public func sendEvent(_ msg: WireMessage) {
        let isTick = msg.params?.value.contains("\"type\":\"tick\"") ?? false
        let isAction = msg.params?.value.contains("\"type\":\"action\"") ?? false
        if isTick {
            // coalesce: if a tick is already queued, skip
            if laneB.contains(where: { $0.params?.value.contains("\"type\":\"tick\"") ?? false }) {
                return
            }
            laneB.append(msg)
        } else if isAction {
            // priority: insert before first pending tick
            if let idx = laneB.firstIndex(where: { $0.params?.value.contains("\"type\":\"tick\"") ?? false }) {
                laneB.insert(msg, at: idx)
            } else {
                laneB.append(msg)
            }
        } else {
            laneB.append(msg)
        }
        drainB()
    }

    // Host -> App: immediate response - bypasses isBusy (Lane A)
    public func sendResponse(_ msg: WireMessage) {
        write(msg)
    }

    private func drainB() {
        guard !isBusy, let next = laneB.first else { return }
        laneB.removeFirst()
        isBusy = true
        write(next)
    }

    private func write(_ msg: WireMessage) {
        guard let h = stdinHandle else { return }
        if let data = try? JSONEncoder().encode(msg), let line = String(data: data, encoding: .utf8) {
            h.write(Data((line + "\n").utf8))
        }
    }

    // App -> Host: handle line from stdout
    public func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONDecoder().decode(WireMessage.self, from: data) else {
            return
        }

        if msg.method == "eventComplete" {
            isBusy = false
            let idle = onIdle
            drainB()
            if laneB.isEmpty {
                idle?()
            }
            return
        }
        if msg.method == "render", let params = msg.params {
            let raw = params.value
            var jsonStr = raw
            if raw.hasPrefix("\""), let d = raw.data(using: .utf8), let unquoted = try? JSONDecoder().decode(String.self, from: d) {
                jsonStr = unquoted
            }
            if let d = jsonStr.data(using: .utf8), let payload = try? JSONDecoder().decode(RenderPayload.self, from: d) {
                onRender?(payload)
            }
            return
        }
        // host.* calls - dispatch and reply via Lane A immediately
        if let method = msg.method, method.hasPrefix("host.") {
            Task { await self.dispatchHostCall(msg) }
            return
        }
    }

    private func dispatchHostCall(_ msg: WireMessage) async {
        guard let id = msg.id, let method = msg.method else { return }
        if let perms = permissions, let denied = await perms.checkOrDeny(appId: appId, method: method) {
            fputs("[perm] denied \(appId) \(method): \(denied)\n", stderr)
            let reply = WireMessage(id: id, result: AnyCodable("{\"error\":\"\(denied)\"}"))
            sendResponse(reply)
            return
        }
        let paramsStr = msg.params?.value ?? "{}"
        let paramsDict: [String: String] = {
            if let d = paramsStr.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: String] { return j }
            // if params was quoted string containing JSON
            if paramsStr.hasPrefix("\""), let d2 = paramsStr.data(using: .utf8), let s = try? JSONDecoder().decode(String.self, from: d2), let d3 = s.data(using: .utf8), let j2 = try? JSONSerialization.jsonObject(with: d3) as? [String: String] { return j2 }
            return [:]
        }()

        var resultStr = ""
        switch method {
        case "host.store.get":
            let key = paramsDict["key"] ?? ""
            let v = await store?.get(appId: appId, key: key) ?? ""
            // return as JSON string value (host shim does JSON.parse)
            resultStr = v.isEmpty ? "" : v
        case "host.store.set":
            let key = paramsDict["key"] ?? ""
            let value = paramsDict["value"] ?? ""
            try? await store?.set(appId: appId, key: key, value: value)
            resultStr = "ok"
        case "host.shell.exec":
            let cmd = paramsDict["cmd"] ?? paramsDict["command"] ?? ""
            if let shell {
                let r = await shell.exec(command: cmd)
                let obj: [String: String] = ["stdout": r.stdout, "stderr": r.stderr, "exitCode": "\(r.exitCode)"]
                if let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) { resultStr = s }
            }
        case "host.shell.spawn":
            let cmd = paramsDict["cmd"] ?? paramsDict["command"] ?? ""
            let aid = appId
            if let shell {
                let spawned = await shell.spawn(command: cmd) { out in
                    fputs("[shell \(aid)] \(out)", stderr)
                    // v2: stream to App via event {type:"shell.output"}
                }
                if let s = spawned, let d = try? JSONEncoder().encode(s), let str = String(data: d, encoding: .utf8) {
                    resultStr = str
                } else {
                    resultStr = "{\"error\":\"spawn failed\"}"
                }
            }
        case "host.secrets.get":
            let key = paramsDict["key"] ?? ""
            // v1: store in Store under secrets: prefix (v2: Keychain)
            let v = await store?.get(appId: appId, key: "secrets:\(key)") ?? ""
            resultStr = v
        case "host.secrets.set":
            let key = paramsDict["key"] ?? ""
            let value = paramsDict["value"] ?? ""
            try? await store?.set(appId: appId, key: "secrets:\(key)", value: value)
            resultStr = "ok"
        case "host.fetch":
            let urlStr = paramsDict["url"] ?? ""
            let method = paramsDict["method"] ?? "GET"
            if let url = URL(string: urlStr) {
                var req = URLRequest(url: url)
                req.httpMethod = method
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let obj: [String: String] = ["status": "\(status)", "body": body]
                    if let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) { resultStr = s }
                    else { resultStr = body }
                } catch {
                    resultStr = "{\"error\":\"\(error.localizedDescription)\"}"
                }
            } else {
                resultStr = "{\"error\":\"invalid url\"}"
            }
        case "host.notify":
            let title = paramsDict["title"] ?? "Orchestrator"
            let body = paramsDict["body"] ?? paramsDict["message"] ?? ""
            fputs("[notify \(appId)] \(title): \(body)\n", stderr)
            // UNUserNotificationCenter crashes in CLI (no bundle), so just log for v1
            // v2: when running as .app bundle, enable via #if canImport and bundle check
            resultStr = "ok"
        default:
            resultStr = "{\"error\":\"unknown method \(method)\"}"
        }
        // reply via Lane A (immediate)
        let reply = WireMessage(id: id, result: AnyCodable(resultStr))
        sendResponse(reply)
    }

    public func markIdle() { isBusy = false; drainB() }
}
