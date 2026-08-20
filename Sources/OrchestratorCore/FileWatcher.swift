import Foundation

public actor FileWatcher {
    private var appsRoot: URL
    private var onChange: (([Manifest]) -> Void)?
    private var task: Task<Void, Never>?
    private var lastManifests: [String: String] = [:] // id -> hash of manifest data

    public init(appsRoot: URL) { self.appsRoot = appsRoot }

    public func start(onChange: @escaping ([Manifest]) -> Void) {
        self.onChange = onChange
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.check()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func check() async {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: appsRoot, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        var current: [String: String] = [:]
        var manifests: [Manifest] = []
        for dir in entries where dir.hasDirectoryPath {
            let mf = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: mf.path), let data = try? Data(contentsOf: mf) else { continue }
            let hash = hash(data: data)
            if let m = try? JSONDecoder().decode(Manifest.self, from: data) {
                // check enabled
                if m.enabled == false { continue }
                current[m.id] = hash
                manifests.append(m)
            }
        }
        if current != lastManifests {
            lastManifests = current
            onChange?(manifests)
        }
    }

    private func hash(data: Data) -> String {
        // simple hash: base64 of first 32 bytes
        return data.prefix(64).base64EncodedString()
    }
}
