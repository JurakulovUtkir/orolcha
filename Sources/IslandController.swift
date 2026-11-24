import AppKit
import ServiceManagement
import SwiftUI

/// Ramkasiz, fokus olmaydigan, menyu paneldan yuqorida turadigan oyna.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onRightClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}

final class BlockMenuItem: NSMenuItem {
    private let block: () -> Void

    init(_ title: String, checked: Bool = false, _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) yo'q") }

    @objc private func fire() { block() }
}

final class IslandController {
    static let windowSize = CGSize(width: 780, height: 300)

    private let panel = IslandPanel()
    private let model: IslandModel
    private var monitors: [Any] = []
    private var observers: [Any] = []
    private var pollTimer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        model = IslandModel(metrics: ScreenMetrics.make(for: NSScreen.screens.first ?? NSScreen.main!,
                                                        preferNotchLook: UserDefaults.standard.bool(forKey: "notchLook")))
    }

    func start() {
        let host = IslandHostingView(rootView: IslandRootView(model: model))
        host.sizingOptions = []
        host.onRightClick = { [weak self] in self?.showMenu() }
        model.onMenu = { [weak self] in self?.showMenu() }
        panel.contentView = host
        place()
        panel.orderFrontRegardless()

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.trackMouse()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] e in
            self?.trackMouse()
            return e
        }) { monitors.append(m) }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.place()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.orderFrontRegardless()
        })

        model.music.start()
        model.claude.start { [weak self] in self?.debugState() ?? [:] }
        model.calendar.start()
    }

    func stop() {
        model.music.stop()
        monitors.forEach { NSEvent.removeMonitor($0) }
    }

    // MARK: Joylashuv

    private func chooseScreen() -> NSScreen {
        let screens = NSScreen.screens
        if !defaults.bool(forKey: "preferMainScreen"),
           let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return screens.first ?? NSScreen.main!
    }

    private func place() {
        let screen = chooseScreen()
        let m = ScreenMetrics.make(for: screen, preferNotchLook: defaults.bool(forKey: "notchLook"))
        if m != model.metrics { model.metrics = m }
        let f = screen.frame
        let w = Self.windowSize.width, h = Self.windowSize.height
        panel.setFrame(NSRect(x: (f.midX - w / 2).rounded(), y: f.maxY - h, width: w, height: h), display: true)
    }

    // MARK: Sichqoncha

    private func hitRect() -> NSRect {
        let mode = model.mode
        let s = model.geometry.frame(mode)
        let f = model.metrics.frame
        let pad: CGFloat = mode == .expanded ? 14 : 6
        let inset = model.geometry.topInset
        return NSRect(x: f.midX - s.width / 2 - pad, y: f.maxY - inset - s.height - pad,
                      width: s.width + 2 * pad, height: inset + s.height + pad + 2)
    }

    private func trackMouse() {
        let inside = hitRect().contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.setHovering(inside)
        if inside {
            if pollTimer == nil {
                // Ichkarida turganda chiqib ketishni ishonchli sezish uchun yengil so'rov.
                pollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.trackMouse() }
            }
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func debugState() -> [String: Any] {
        let m = model
        var music: [String: Any] = ["artwork": m.music.artwork != nil, "app": m.music.appName]
        if let n = m.music.now {
            music["title"] = n.title
            music["artist"] = n.artist
            music["playing"] = n.playing
            music["position"] = Int(n.position(at: Date()))
            music["duration"] = Int(n.duration)
        }
        return [
            "mode": "\(m.mode)",
            "screen": ["notch": m.metrics.hasNotch, "width": m.metrics.notch.width, "height": m.metrics.notch.height],
            "music": music,
            "claude": m.claude.sessions.map { ["project": $0.project, "state": "\($0.state)", "detail": $0.detail, "app": $0.appBundle ?? ""] },
            "calendar": ["access": "\(m.calendar.access)", "events": m.calendar.events.map { $0.title }],
            "peek": m.peek?.title ?? "",
            "loginItem": ["notRegistered", "enabled", "requiresApproval", "notFound"][min(3, SMAppService.mainApp.status.rawValue)],
        ]
    }

    // MARK: Menyu

    private func showMenu() {
        let menu = NSMenu()
        if NSScreen.screens.count > 1, NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }) {
            let on = defaults.bool(forKey: "preferMainScreen")
            menu.addItem(BlockMenuItem("Asosiy ekranda koʻrsatish", checked: on) { [weak self] in
                self?.defaults.set(!on, forKey: "preferMainScreen")
                self?.place()
            })
        }
        if !model.metrics.hasNotch {
            let notchLook = defaults.bool(forKey: "notchLook")
            menu.addItem(BlockMenuItem("Notch koʻrinishi (kapsula oʻrniga)", checked: notchLook) { [weak self] in
                self?.defaults.set(!notchLook, forKey: "notchLook")
                self?.place()
            })
        }
        let login = SMAppService.mainApp.status == .enabled
        menu.addItem(BlockMenuItem("Kompyuter yoqilganda ishga tushsin", checked: login) {
            if login { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
        })
        if model.calendar.access != .granted {
            menu.addItem(BlockMenuItem("Kalendarga ruxsat berish…") { [weak self] in self?.model.calendar.requestOrOpenSettings() })
        }
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem("Orolchadan chiqish") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
