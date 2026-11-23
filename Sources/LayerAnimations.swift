import AppKit
import QuartzCore
import SwiftUI

// Doimiy animatsiyalar Core Animation'da: render-server chizadi, ilova CPU'si deyarli band bo'lmaydi.

enum Rays {
    /// Claude yulduzchasi: 10 ta nur, navbatma-navbat uzun/qisqa.
    static func path(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = max(1.4, r * 0.24)
        for i in 0..<10 {
            let angle = CGFloat(i) / 10 * 2 * .pi
            let len = r * (i % 2 == 0 ? 0.92 : 0.72)
            let ray = CGPath(roundedRect: CGRect(x: -w / 2, y: -len, width: w, height: len),
                             cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
            var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
            if let moved = ray.copy(using: &t) { p.addPath(moved) }
        }
        return p
    }
}

struct RaysShape: Shape {
    func path(in rect: CGRect) -> Path { Path(Rays.path(in: rect)) }
}

/// Claude yulduzchasi: ishlayotganda aylanadi va "nafas oladi", kutayotganda miltillaydi.
struct ClaudeGlyph: View {
    var state: ClaudeSession.State

    var body: some View {
        if Snapshot.isRendering {
            RaysShape().fill(color)
        } else {
            GlyphRepresentable(state: state, color: NSColor(color))
        }
    }

    private var color: Color {
        switch state {
        case .working: Palette.claude
        case .waiting: Palette.amber
        case .done: Palette.green
        case .idle: Palette.tertiary
        }
    }
}

private struct GlyphRepresentable: NSViewRepresentable {
    var state: ClaudeSession.State
    var color: NSColor

    func makeNSView(context: Context) -> GlyphNSView { GlyphNSView() }
    func updateNSView(_ v: GlyphNSView, context: Context) { v.update(state: state, color: color) }
}

final class GlyphNSView: NSView {
    private let spin = CALayer()
    private let shape = CAShapeLayer()
    private var state: ClaudeSession.State?
    private var lastSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(spin)
        spin.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yo'q") }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spin.bounds = bounds
        spin.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shape.bounds = bounds
        shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shape.path = Rays.path(in: bounds)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        let s = window?.backingScaleFactor ?? 2
        shape.contentsScale = s
        spin.contentsScale = s
    }

    override func viewDidMoveToWindow() {
        // Oyna almashganda animatsiyalarni qayta qo'yamiz.
        if let s = state { state = nil; apply(s) }
    }

    func update(state: ClaudeSession.State, color: NSColor) {
        shape.fillColor = color.cgColor
        guard state != self.state else { return }
        apply(state)
    }

    private func apply(_ state: ClaudeSession.State) {
        self.state = state
        spin.removeAllAnimations()
        shape.removeAllAnimations()
        switch state {
        case .working:
            let r = CABasicAnimation(keyPath: "transform.rotation.z")
            r.fromValue = 0
            r.toValue = -2 * Double.pi
            r.duration = 3.6
            r.repeatCount = .infinity
            spin.add(r, forKey: "spin")
            let b = CAKeyframeAnimation(keyPath: "transform.scale")
            b.values = [1, 0.8, 1]
            b.keyTimes = [0, 0.5, 1]
            b.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            b.duration = 1.5
            b.repeatCount = .infinity
            shape.add(b, forKey: "breath")
        case .waiting:
            let o = CABasicAnimation(keyPath: "opacity")
            o.fromValue = 1
            o.toValue = 0.4
            o.duration = 0.7
            o.autoreverses = true
            o.repeatCount = .infinity
            o.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shape.add(o, forKey: "blink")
        case .done, .idle:
            break
        }
    }
}

/// Musiqa to'lqini — muqova rangida.
struct Waveform: View {
    var color: Color
    var playing: Bool

    var body: some View {
        if Snapshot.isRendering {
            HStack(spacing: 2.2) {
                ForEach([0.55, 1.0, 0.4, 0.8], id: \.self) { v in
                    Capsule().fill(color).frame(height: 13 * v)
                }
            }
        } else {
            WaveRepresentable(color: NSColor(color), playing: playing)
        }
    }
}

private struct WaveRepresentable: NSViewRepresentable {
    var color: NSColor
    var playing: Bool

    func makeNSView(context: Context) -> WaveNSView { WaveNSView() }
    func updateNSView(_ v: WaveNSView, context: Context) { v.update(color: color, playing: playing) }
}

final class WaveNSView: NSView {
    private var bars: [CALayer] = []
    private var playing: Bool?
    private var lastSize: CGSize = .zero

    private static let patterns: [[CGFloat]] = [
        [0.35, 1.0, 0.55, 0.9, 0.4, 0.75, 0.35],
        [0.6, 0.3, 0.95, 0.5, 1.0, 0.45, 0.6],
        [0.45, 0.85, 0.35, 1.0, 0.6, 0.3, 0.45],
        [0.8, 0.5, 0.7, 0.35, 0.9, 0.6, 0.8],
    ]
    private static let durations: [CFTimeInterval] = [1.3, 1.1, 1.45, 1.2]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let b = CALayer()
            layer?.addSublayer(b)
            bars.append(b)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yo'q") }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        let gap: CGFloat = 2.2
        let w = (bounds.width - gap * 3) / 4
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, b) in bars.enumerated() {
            b.bounds = CGRect(x: 0, y: 0, width: w, height: max(w, bounds.height * 0.35))
            b.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            b.cornerRadius = w / 2
        }
        CATransaction.commit()
        restart()
    }

    override func viewDidMoveToWindow() { restart() }

    func update(color: NSColor, playing: Bool) {
        bars.forEach { $0.backgroundColor = color.cgColor }
        guard playing != self.playing else { return }
        self.playing = playing
        restart()
    }

    private func restart() {
        let h = bounds.height
        for (i, b) in bars.enumerated() {
            b.removeAnimation(forKey: "wave")
            guard playing == true, h > 0 else { continue }
            let a = CAKeyframeAnimation(keyPath: "bounds.size.height")
            a.values = Self.patterns[i].map { max(b.bounds.width, $0 * h) }
            a.duration = Self.durations[i]
            a.repeatCount = .infinity
            a.calculationMode = .cubic
            b.add(a, forKey: "wave")
        }
    }
}
