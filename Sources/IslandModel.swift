import AppKit
import SwiftUI

struct Peek: Identifiable, Equatable {
    enum Kind: Equatable { case claudeDone, claudeWaiting, calendar }
    let id = UUID()
    var kind: Kind
    var title: String
    var subtitle: String
}

/// Orolchaning umumiy holati: ochiq/yopiq, qisqa xabar (peek) va bo'limlar.
final class IslandModel: ObservableObject {
    @Published var metrics: ScreenMetrics
    @Published private(set) var expanded = false
    @Published private(set) var peek: Peek?

    let music = MusicModel()
    let claude = ClaudeModel()
    let calendar = CalendarModel()

    var onMenu: (() -> Void)?

    private var hovering = false
    private var hoverWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?

    init(metrics: ScreenMetrics) {
        self.metrics = metrics
        claude.onEvent = { [weak self] event in self?.handleClaude(event) }
        calendar.onSoon = { [weak self] ev in
            self?.showPeek(Peek(kind: .calendar, title: ev.title, subtitle: "\(UzTime.until(ev.start)) boshlanadi"), duration: 6)
        }
    }

    var geometry: IslandGeometry { IslandGeometry(m: metrics) }

    var mode: IslandMode {
        if expanded { return .expanded }
        if peek != nil { return .peek }
        if music.isPlaying || claude.hasActive { return .live }
        return .idle
    }

    func setHovering(_ h: Bool) {
        guard h != hovering else { return }
        hovering = h
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.hovering { self.expand() } else { self.collapse() }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (h ? 0.12 : 0.3), execute: work)
    }

    func expand() {
        guard !expanded else { return }
        peekWork?.cancel()
        peek = nil
        expanded = true
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        calendar.reload()
        music.refresh()
    }

    func collapse() {
        guard expanded else { return }
        expanded = false
    }

    func showPeek(_ p: Peek, duration: Double = 3.6) {
        guard !expanded else { return }
        peek = p
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.peek?.id == p.id { self?.peek = nil }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func handleClaude(_ event: ClaudeEvent) {
        switch event {
        case .finished(let s):
            let took = s.workStarted.map { UzTime.duration(Date().timeIntervalSince($0)) } ?? ""
            showPeek(Peek(kind: .claudeDone, title: "\(s.project) — tugadi", subtitle: took.isEmpty ? s.prompt : "\(took) · \(s.prompt)"))
        case .waiting(let s):
            showPeek(Peek(kind: .claudeWaiting, title: "\(s.project) — javob kutmoqda", subtitle: s.detail), duration: 5)
        }
    }
}

/// O'zbekcha vaqt matnlari.
enum UzTime {
    static let weekdays = ["Yakshanba", "Dushanba", "Seshanba", "Chorshanba", "Payshanba", "Juma", "Shanba"]
    static let months = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentabr", "oktabr", "noyabr", "dekabr"]

    static func header(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.weekday, .day, .month], from: d)
        return "\(weekdays[(c.weekday ?? 1) - 1]), \(c.day ?? 1)-\(months[(c.month ?? 1) - 1])"
    }

    static func clock(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        if s < 60 { return "\(s) son" }
        let m = s / 60
        if m < 60 { return "\(m) daq" }
        return m % 60 == 0 ? "\(m / 60) soat" : "\(m / 60) soat \(m % 60) daq"
    }

    /// "5 daqiqadan soʻng" kabi.
    static func until(_ d: Date) -> String {
        let m = Int((d.timeIntervalSinceNow / 60).rounded(.up))
        if m <= 0 { return "hozir" }
        if m < 60 { return "\(m) daqiqadan soʻng" }
        return "\(m / 60) soat \(m % 60) daqiqadan soʻng"
    }

    /// Taymer: 0:42, 12:05, 1:02:10.
    static func timer(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
