import AppKit
import ImageIO
import SwiftUI

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var rate: Double
    var timestamp: Date
    var playing: Bool
    var bundleID: String?

    func position(at date: Date) -> Double {
        var p = elapsed
        if playing { p += date.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1) }
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// Har qanday pleyer (Yandex Music, Spotify, Music, brauzer, Telegram) — MediaRemote ko'prigi orqali.
final class MusicModel: ObservableObject {
    static let fallbackAccent = Color(white: 0.92)

    @Published private(set) var now: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = MusicModel.fallbackAccent
    @Published private(set) var appName = ""
    @Published private(set) var appIcon: NSImage?

    var isPlaying: Bool { now?.playing == true }

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private let parseQueue = DispatchQueue(label: "orolcha.music.parse", qos: .userInitiated)
    private var stopping = false
    private var restartDelay: Double = 1
    private var appBundle: String?

    private enum Art { case new(NSImage, Color), same, none }

    private struct Update {
        var now: NowPlaying?
        var art: Art
    }

    // MARK: Ko'prik jarayoni

    func start() {
        guard let res = Bundle.main.resourceURL else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [res.appendingPathComponent("media-bridge.pl").path,
                       res.appendingPathComponent("MediaBridge.dylib").path]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.parseQueue.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.bridgeDied() }
        }
        do {
            try p.run()
            process = p
            input = inp.fileHandleForWriting
        } catch {
            bridgeDied()
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
    }

    private func bridgeDied() {
        process = nil
        input = nil
        guard !stopping else { return }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.parseQueue.async { self?.buffer.removeAll() }
            self?.start()
        }
    }

    private func send(_ line: String) {
        guard let input, let data = (line + "\n").data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }

    // MARK: Buyruqlar

    func refresh() { send("refresh") }
    func next() { send("next") }
    func previous() { send("prev") }

    func togglePlay() {
        guard var n = now else { send("toggle"); return }
        n.elapsed = n.position(at: Date())
        n.timestamp = Date()
        n.playing.toggle()
        now = n
        send("toggle")
    }

    func seek(to t: Double) {
        guard var n = now else { return }
        n.elapsed = t
        n.timestamp = Date()
        now = n
        send("seek \(t)")
    }

    func openSourceApp() {
        AppOpener.activate(bundleID: appBundle ?? "ru.yandex.desktop.music")
    }

    // MARK: Snapshot rejimi uchun

    func demoSet(_ n: NowPlaying, artwork img: NSImage) {
        now = n
        appBundle = n.bundleID
        artwork = img
        if let tiff = img.tiffRepresentation { accent = Self.vividColor(of: tiff) }
        if let id = n.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
            appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
    }

    func demoPause() { now?.playing = false }

    // MARK: JSON tahlili (fon navbatida)

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  obj["type"] as? String == "info" else { continue }
            let update = Self.makeUpdate(obj)
            DispatchQueue.main.async { [weak self] in self?.apply(update) }
        }
    }

    private static func makeUpdate(_ o: [String: Any]) -> Update {
        let title = (o["title"] as? String) ?? ""
        guard !title.isEmpty else { return Update(now: nil, art: .none) }
        let bundle = (o["parentBundle"] as? String) ?? (o["bundle"] as? String)
        let n = NowPlaying(
            title: title,
            artist: (o["artist"] as? String) ?? "",
            album: (o["album"] as? String) ?? "",
            duration: (o["duration"] as? Double) ?? 0,
            elapsed: (o["elapsed"] as? Double) ?? 0,
            rate: (o["rate"] as? Double) ?? 0,
            timestamp: (o["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            playing: (o["playing"] as? Bool) ?? false,
            bundleID: bundle
        )
        var art = Art.none
        if let b64 = o["artwork"] as? String, let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
            art = .new(img, vividColor(of: data))
        } else if o["artworkSame"] != nil {
            art = .same
        }
        return Update(now: n, art: art)
    }

    private func apply(_ u: Update) {
        if now != u.now { now = u.now }
        switch u.art {
        case .new(let img, let color):
            artwork = img
            accent = color
        case .same:
            break
        case .none:
            if artwork != nil { artwork = nil; accent = Self.fallbackAccent }
        }
        if let b = u.now?.bundleID, b != appBundle {
            appBundle = b
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                appIcon = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                appName = ""
                appIcon = nil
            }
        }
    }

    /// Muqovadagi eng yorqin, to'yingan rang — progress va to'lqin uchun.
    private static func vividColor(of data: Data) -> Color {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return fallbackAccent }
        let w = 12, h = 12
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return fallbackAccent }
        var best: (score: CGFloat, h: CGFloat, s: CGFloat, b: CGFloat) = (-1, 0, 0, 0)
        for i in stride(from: 0, to: px.count, by: 4) {
            let c = NSColor(deviceRed: CGFloat(px[i]) / 255, green: CGFloat(px[i + 1]) / 255, blue: CGFloat(px[i + 2]) / 255, alpha: 1)
            var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            c.getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
            guard bb > 0.25 else { continue }
            let score = ss * 0.75 + bb * 0.25
            if score > best.score { best = (score, hh, ss, bb) }
        }
        if best.s < 0.2 { return fallbackAccent }
        return Color(hue: Double(best.h), saturation: Double(min(0.85, max(0.5, best.s))), brightness: Double(max(0.88, best.b)))
    }
}
