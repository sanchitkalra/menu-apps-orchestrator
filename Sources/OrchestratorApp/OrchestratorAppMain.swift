#if canImport(SwiftUI)
import SwiftUI
import OrchestratorCore

@MainActor
final class HostModel: ObservableObject {
    @Published var renders: [String: RenderPayload] = [:]
    @Published var sizes: [String: String] = [:]   // appId -> manifest tile.size ("1x1"/"2x1"/"2x2")
    private var supervisor: ProcessSupervisor?
    private var scheduler: Scheduler?

    // ponytail: Apps/ + Data/ under ~/Orchestrator, same defaults as the CLI host
    let appsRoot = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Orchestrator/Apps")
    let dataRoot = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Orchestrator/Data")

    func start() {
        guard supervisor == nil else { return }
        try? FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)

        let sup = ProcessSupervisor(store: Store(root: dataRoot), shell: ShellGateway(), permissions: PermissionManager()) { [weak self] appId, payload in
            Task { @MainActor in self?.renders[appId] = payload }
        }
        let sched = Scheduler { appId in Task { await sup.sendTick(appId: appId) } }
        supervisor = sup
        scheduler = sched

        let apps = appsRoot, data = dataRoot
        Task {
            for m in (try? await AppRegistry(appsRoot: apps).scan()) ?? [] {
                let size = m.tile?.size ?? "1x1"
                await MainActor.run { self.sizes[m.id] = size }
                await sup.register(manifest: m)
                try? await sup.spawn(appId: m.id, appsRoot: apps, dataRoot: data)
                await sched.register(appId: m.id, schedule: m.schedule)
            }
        }
    }

    func send(appId: String, actionId: String, payload: [String: String]? = nil) {
        guard let supervisor else { return }
        Task { await supervisor.sendAction(appId: appId, actionId: actionId, payload: payload) }
    }
}

// ponytail: menu-bar-only app has no windows, so macOS is free to auto-terminate it.
// Keeping a delegate is the smallest thing that pins it alive without an .app bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // MenuBarExtra's panel closes on a click outside, but Mission Control / app switching
        // never sends that click, so the popover stays up. Close it when another app takes over.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let other = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard other?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            // NSApp.hide dismisses MenuBarExtraWindow; no private class names needed
            NSApp.hide(nil)
        }
    }
}

@main
struct OrchestratorApp: App {
    @StateObject private var model = HostModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar host")
        ProcessInfo.processInfo.disableSuddenTermination()
        // ponytail: spawn apps at launch, not when the popover first opens
        let m = HostModel()
        m.start()
        _model = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        MenuBarExtra("Orchestrator", systemImage: "square.grid.2x2") {
            GridWindowView(model: model)
                .frame(width: 348)
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
