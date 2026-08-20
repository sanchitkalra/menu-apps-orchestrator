import Foundation

public actor PermissionManager {
    private var manifests: [String: Manifest] = [:]
    // For v1, permissions are just strings like "store", "fetch", "shell.exec", "shell.spawn", "notify", "secrets"
    // If manifest.permissions is empty, deny all host.* except render
    public init() {}

    public func register(manifest: Manifest) {
        manifests[manifest.id] = manifest
    }

    public func unregister(appId: String) {
        manifests.removeValue(forKey: appId)
    }

    public func isAllowed(appId: String, method: String) -> Bool {
        guard let m = manifests[appId] else { return false }
        // render and eventComplete are always allowed (not host.*)
        if !method.hasPrefix("host.") { return true }
        let perm = method.replacingOccurrences(of: "host.", with: "")
        // exact match or prefix match (e.g., "shell" allows "shell.exec" and "shell.spawn")
        for p in m.permissions {
            if p == perm || perm.hasPrefix(p + ".") || p == "*" { return true }
            // allow "shell" to cover "shell.exec"
            if p == "shell" && perm.hasPrefix("shell.") { return true }
            if p == "store" && perm.hasPrefix("store.") { return true }
        }
        return false
    }

    public func checkOrDeny(appId: String, method: String) -> String? {
        if isAllowed(appId: appId, method: method) { return nil }
        return "Permission denied: \(method) not in \(manifests[appId]?.permissions ?? []) for \(appId)"
    }
}
