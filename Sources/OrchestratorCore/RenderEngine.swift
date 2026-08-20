import Foundation

public actor RenderEngine {
    private var lastRenders: [String: RenderPayload] = [:]
    private var onUpdate: ((String, RenderPayload) -> Void)?

    public init(onUpdate: ((String, RenderPayload) -> Void)? = nil) {
        self.onUpdate = onUpdate
    }

    public func apply(appId: String, payload: RenderPayload) {
        // Validate: ensure tile/detail are within allowed DSL (already decoded)
        // Diff: simple equality check for now; real impl does tree diff with keys
        if let last = lastRenders[appId], last.tile == payload.tile, last.detail == payload.detail {
            return // no change
        }
        lastRenders[appId] = payload
        onUpdate?(appId, payload)
        persist(appId: appId, payload: payload)
    }

    public func lastRender(for appId: String) -> RenderPayload? { lastRenders[appId] }

    private func persist(appId: String, payload: RenderPayload) {
        // persist to Data/<appId>/lastRender.json for cold start tiles
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Orchestrator/Data/\(appId)/lastRender.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func loadPersisted(appId: String) -> RenderPayload? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Orchestrator/Data/\(appId)/lastRender.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RenderPayload.self, from: data)
    }
}

extension RenderPayload: Equatable {
    public static func == (lhs: RenderPayload, rhs: RenderPayload) -> Bool {
        // encode and compare for Equatable
        guard let l = try? JSONEncoder().encode(lhs), let r = try? JSONEncoder().encode(rhs) else { return false }
        return l == r
    }
}
