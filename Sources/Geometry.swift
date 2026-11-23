import AppKit
import SwiftUI

/// Ekran va notch o'lchamlari.
struct ScreenMetrics: Equatable {
    var notch: CGSize
    var hasNotch: Bool
    var frame: CGRect

    static func make(for screen: NSScreen) -> ScreenMetrics {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0,
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let w = max(120, f.width - l.width - r.width)
            return ScreenMetrics(notch: CGSize(width: w, height: screen.safeAreaInsets.top), hasNotch: true, frame: f)
        }
        // Notch yo'q ekran (tashqi monitor) — menyu panel balandligida soxta notch.
        var bar = f.maxY - screen.visibleFrame.maxY
        if bar < 18 || bar > 44 { bar = 24 }
        return ScreenMetrics(notch: CGSize(width: 168, height: bar), hasNotch: false, frame: f)
    }
}

enum IslandMode: Equatable {
    case idle, live, peek, expanded
}

struct IslandGeometry {
    let m: ScreenMetrics

    static let expandedWidth: CGFloat = 640
    static let expandedContent: CGFloat = 206
    static let peekContent: CGFloat = 50

    var slot: CGFloat { m.notch.height + 12 }

    /// Tana o'lchami (yuqoridagi "quloqlar"siz).
    func body(_ mode: IslandMode) -> CGSize {
        let n = m.notch
        switch mode {
        case .idle: return n
        case .live: return CGSize(width: n.width + 2 * slot, height: n.height)
        case .peek: return CGSize(width: max(n.width + 2 * slot, 340), height: n.height + Self.peekContent)
        case .expanded: return CGSize(width: Self.expandedWidth, height: n.height + Self.expandedContent)
        }
    }

    func topRadius(_ mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle, .live: return 6
        case .peek: return 10
        case .expanded: return 14
        }
    }

    func bottomRadius(_ mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle: return m.hasNotch ? 10 : 9
        case .live: return 12
        case .peek: return 22
        case .expanded: return 32
        }
    }

    /// Ramka o'lchami (quloqlar bilan).
    func frame(_ mode: IslandMode) -> CGSize {
        let b = body(mode)
        return CGSize(width: b.width + 2 * topRadius(mode), height: b.height)
    }
}

/// Notch shakli: tepada ichkariga botiq "quloqlar", pastda yumaloq burchaklar.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(top, rect.width / 4)
        let b = min(bottom, (rect.width - 2 * t) / 2, rect.height - t)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
