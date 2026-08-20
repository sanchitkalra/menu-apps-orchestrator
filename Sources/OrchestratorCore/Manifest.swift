import Foundation

public enum Lifecycle: String, Codable, Sendable {
    case ephemeral
    case persistent
    case resident
}

public struct TileConfig: Codable, Sendable {
    public var size: String // "1x1" | "2x1" | "2x2"
    public init(size: String) { self.size = size }
}

public struct ScheduleConfig: Codable, Sendable {
    public var interval: String? // "5m", "60s", "1h"
    public var cron: String?
    public var onOverlap: String? // "skip" | "queue"
    public init(interval: String? = nil, cron: String? = nil, onOverlap: String? = "skip") {
        self.interval = interval; self.cron = cron; self.onOverlap = onOverlap
    }
}

public struct Manifest: Codable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var entrypoint: String
    public var lifecycle: Lifecycle
    public var tile: TileConfig?
    public var schedule: ScheduleConfig?
    public var permissions: [String]
    public var healthcheck: HealthcheckConfig?
    public var enabled: Bool?

    public struct HealthcheckConfig: Codable, Sendable {
        public var interval: String?
        public var timeout: String?
    }

    public init(id: String, name: String, version: String = "0.1.0",
                entrypoint: String, lifecycle: Lifecycle = .ephemeral,
                tile: TileConfig? = nil, schedule: ScheduleConfig? = nil,
                permissions: [String] = [], healthcheck: HealthcheckConfig? = nil, enabled: Bool? = true) {
        self.id = id; self.name = name; self.version = version
        self.entrypoint = entrypoint; self.lifecycle = lifecycle
        self.tile = tile; self.schedule = schedule
        self.permissions = permissions; self.healthcheck = healthcheck; self.enabled = enabled
    }
}

public extension Manifest {
    static func load(from url: URL) throws -> Manifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }
}
