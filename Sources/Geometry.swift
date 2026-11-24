import AppKit
import SwiftUI

/// Ko'rinish uslubi: notch'ga yopishgan yoki iPhone'dagidek alohida kapsula.
enum IslandStyle: Equatable {
    case notch, pill
}

/// Ekran va orolcha o'lchamlari.
struct ScreenMetrics: Equatable {
    /// Notch uslubida — jismoniy (yoki soxta) notch; kapsula uslubida — bo'sh turgandagi kapsula.
    var notch: CGSize
    var hasNotch: Bool
    var frame: CGRect
    var menuBar: CGFloat
    var style: IslandStyle

    static func make(for screen: NSScreen, preferNotchLook: Bool) -> ScreenMetrics {
        let f = screen.frame
        if screen.safeAreaInsets.top > 0,
           let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let w = max(120, f.width - l.width - r.width)
            let h = screen.safeAreaInsets.top
            return ScreenMetrics(notch: CGSize(width: w, height: h), hasNotch: true, frame: f, menuBar: h, style: .notch)
        }
        var bar = f.maxY - screen.visibleFrame.maxY
        if bar < 18 || bar > 44 { bar = 24 }
        if preferNotchLook {
            return ScreenMetrics(notch: CGSize(width: 168, height: bar), hasNotch: false, frame: f, menuBar: bar, style: .notch)
        }
        // Notch yo'q ekran: menyu panel ichida, o'rtada suzib turgan kapsula.
        let h = min(28, max(20, bar - 6))
        return ScreenMetrics(notch: CGSize(width: 108, height: h), hasNotch: false, frame: f, menuBar: bar, style: .pill)
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

    var style: IslandStyle { m.style }
    var isPill: Bool { m.style == .pill }

    /// Kapsula ekran tepasidan qancha pastda turadi (menyu panel o'rtasida).
    var topInset: CGFloat { isPill ? max(2, ((m.menuBar - m.notch.height) / 2).rounded()) : 0 }

    var slot: CGFloat { isPill ? m.notch.height + 12 : m.notch.height + 12 }

    /// Jonli holatda chap va o'ng bo'laklar orasidagi bo'shliq (notch o'rni).
    var liveGap: CGFloat { isPill ? 92 : m.notch.width }

    /// Ochiq holatning yuqori qatori (sana) balandligi.
    var headerHeight: CGFloat { isPill ? 38 : m.notch.height }

    /// Tana o'lchami (yuqoridagi "quloqlar"siz).
    func body(_ mode: IslandMode) -> CGSize {
        let n = m.notch
        switch mode {
        case .idle: return n
        case .live: return CGSize(width: liveGap + 2 * slot, height: n.height)
        case .peek:
            return isPill ? CGSize(width: 340, height: 60)
                          : CGSize(width: max(n.width + 2 * slot, 340), height: n.height + Self.peekContent)
        case .expanded:
            return CGSize(width: Self.expandedWidth, height: headerHeight + Self.expandedContent - (isPill ? 10 : 0))
        }
    }

    func topRadius(_ mode: IslandMode) -> CGFloat {
        if isPill { return 0 }
        switch mode {
        case .idle, .live: return 6
        case .peek: return 10
        case .expanded: return 14
        }
    }

    func bottomRadius(_ mode: IslandMode) -> CGFloat {
        if isPill {
            switch mode {
            case .idle, .live: return m.notch.height / 2
            case .peek: return 30
            case .expanded: return 38
            }
        }
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

    func shape(_ mode: IslandMode) -> IslandShape {
        IslandShape(pill: isPill, top: topRadius(mode), bottom: bottomRadius(mode))
    }
}

/// Ikkala uslub uchun bitta shakl — holatlar orasida radiuslar silliq animatsiya bo'ladi.
struct IslandShape: Shape {
    var pill: Bool
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        if pill {
            let r = min(bottom, rect.height / 2, rect.width / 2)
            return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)
        }
        return NotchShape(top: top, bottom: bottom).path(in: rect)
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
