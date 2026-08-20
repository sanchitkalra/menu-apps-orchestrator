import Foundation

public actor Store {
    private var root: URL
    private var watchers: [String: [(String) -> Void]] = [:] // key = "\(appId):\(key)"
    public init(root: URL) { self.root = root }

    private func fileURL(appId: String) -> URL {
        root.appendingPathComponent(appId).appendingPathComponent("store.json")
    }

    public func get(appId: String, key: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL(appId: appId)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return json[key]
    }

    public func set(appId: String, key: String, value: String) throws {
        let dir = root.appendingPathComponent(appId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var dict: [String: String] = [:]
        if let data = try? Data(contentsOf: fileURL(appId: appId)),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: String] { dict = j }
        dict[key] = value
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL(appId: appId), options: .atomic)
        // notify watchers
        let watchKey = "\(appId):\(key)"
        watchers[watchKey]?.forEach { $0(value) }
    }

    public func watch(appId: String, key: String, handler: @escaping (String) -> Void) {
        let k = "\(appId):\(key)"
        watchers[k, default: []].append(handler)
    }

    // lastRender persist/rehydrate (used by RenderEngine)
    public func saveLastRender(appId: String, payload: RenderPayload) throws {
        let dir = root.appendingPathComponent(appId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("lastRender.json")
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }

    public func loadLastRender(appId: String) -> RenderPayload? {
        let url = root.appendingPathComponent(appId).appendingPathComponent("lastRender.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RenderPayload.self, from: data)
    }

    public func loadAll(appId: String) -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL(appId: appId)),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return j
    }
}
