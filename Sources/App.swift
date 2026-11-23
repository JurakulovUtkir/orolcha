import AppKit
import ServiceManagement

@main
struct OrolchaMain {
    static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        if MainActor.assumeIsolated({ Snapshot.runIfRequested() }) { return }
        let d = AppDelegate()
        delegate = d
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        // `open Orolcha.app --args --enable-login` — kompyuter yoqilganda ishga tushishni yoqadi.
        if CommandLine.arguments.contains("--enable-login") { try? SMAppService.mainApp.register() }
        let c = IslandController()
        controller = c
        c.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

enum AppOpener {
    static func activate(bundleID: String?) {
        guard let id = bundleID, !id.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
