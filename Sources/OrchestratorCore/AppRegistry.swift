import Foundation

public actor AppRegistry {
    private var appsRoot: URL
    private var manifests: [String: Manifest] = [:]
    public init(appsRoot: URL) { self.appsRoot = appsRoot }

    public func scan() throws -> [Manifest] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: appsRoot, includingPropertiesForKeys: nil) else { return [] }
        var out: [Manifest] = []
        for dir in entries where dir.hasDirectoryPath {
            let mf = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: mf.path) else { continue }
            if let m = try? Manifest.load(from: mf) {
                if m.enabled == false { continue }
                manifests[m.id] = m
                out.append(m)
            }
        }
        return out
    }

    public func manifest(for id: String) -> Manifest? { manifests[id] }
    public func all() -> [Manifest] { Array(manifests.values) }
}
