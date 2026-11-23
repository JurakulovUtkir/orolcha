import AppKit
import SwiftUI

/// Tekshiruv va README rasmlari uchun: `Orolcha --snapshot <papka>` har bir holatni
/// namunaviy ma'lumot bilan PNG'ga chizadi (ekran yozish ruxsati kerak emas).
enum Snapshot {
    /// ImageRenderer AppKit ko'rinishlarini chizmaydi — snapshot paytida SwiftUI o'rinbosarlari ishlatiladi.
    static var isRendering = false

    @MainActor static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        isRendering = true
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let backdrop = LinearGradient(colors: [Color(red: 0.32, green: 0.38, blue: 0.72), Color(red: 0.78, green: 0.46, blue: 0.62)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        for notch in [true, false] {
            let metrics = ScreenMetrics(notch: notch ? CGSize(width: 185, height: 32) : CGSize(width: 168, height: 24),
                                        hasNotch: notch, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
            for mode in ["idle", "music", "live", "claude", "peek", "expanded", "empty"] {
                let model = IslandModel(metrics: metrics)
                if mode != "empty" { model.demo(mode) }
                let view = IslandRootView(model: model)
                    .frame(width: IslandController.windowSize.width, height: IslandController.windowSize.height)
                    .background(backdrop)
                let r = ImageRenderer(content: view)
                r.scale = 2
                if let cg = r.cgImage,
                   let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                    guard let srgb = ctx.makeImage() else { continue }
                    let rep = NSBitmapImageRep(cgImage: srgb)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: dir.appendingPathComponent("\(notch ? "notch" : "flat")-\(mode).png"))
                    }
                }
            }
        }
        return true
    }

    /// Namunaviy muqova: gradient va doiralar.
    static func demoArtwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1),
                                NSColor(red: 0.85, green: 0.2, blue: 0.45, alpha: 1)])?.draw(in: rect, angle: -60)
            NSColor(white: 1, alpha: 0.18).setFill()
            NSBezierPath(ovalIn: NSRect(x: 40, y: 60, width: 180, height: 180)).fill()
            NSColor(white: 1, alpha: 0.28).setFill()
            NSBezierPath(ovalIn: NSRect(x: 150, y: 30, width: 110, height: 110)).fill()
            return true
        }
    }
}

extension IslandModel {
    func demo(_ mode: String) {
        if mode != "claude" { music.demo() }
        if mode != "idle" && mode != "music" { claude.demo(working: mode != "peek") }
        switch mode {
        case "idle": music.demoPause()
        case "peek": showPeek(Peek(kind: .claudeDone, title: "my-app — tugadi", subtitle: "4 daq · Login sahifasini tuzat"), duration: 60)
        case "expanded": expand()
        default: break
        }
        calendar.demo()
    }
}

extension MusicModel {
    func demo() {
        demoSet(NowPlaying(title: "Tungi shahar", artist: "Navo", album: "", duration: 214, elapsed: 71, rate: 1,
                           timestamp: Date(), playing: true, bundleID: "ru.yandex.desktop.music"),
                artwork: Snapshot.demoArtwork())
    }
}

extension ClaudeModel {
    func demo(working: Bool) {
        demoSet([
            ClaudeSession(id: "a", project: "my-app", state: working ? .working : .done, detail: "Tahrirlamoqda: LoginView.swift",
                          prompt: "Login sahifasini tuzat", updatedAt: Date(), workStarted: Date().addingTimeInterval(-163),
                          workEnded: working ? nil : Date(), appBundle: nil),
            ClaudeSession(id: "b", project: "website", state: .waiting, detail: "Ruxsat kerak: Bash",
                          prompt: "Deploy skriptini yoz", updatedAt: Date(), workStarted: Date().addingTimeInterval(-40),
                          workEnded: nil, appBundle: nil),
        ].filter { working || $0.id == "a" })
    }
}

extension CalendarModel {
    func demo() {
        let now = Date()
        demoSet([
            CalEvent(id: "1", title: "Jamoa bilan uchrashuv", start: now.addingTimeInterval(25 * 60),
                     end: now.addingTimeInterval(55 * 60), color: .orange, meetingURL: URL(string: "https://meet.google.com/abc")),
            CalEvent(id: "2", title: "Haftalik reja", start: now.addingTimeInterval(26 * 3600),
                     end: now.addingTimeInterval(27 * 3600), color: .purple, meetingURL: nil),
        ])
    }
}
