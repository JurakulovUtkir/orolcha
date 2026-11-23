import AppKit
import SwiftUI

enum Palette {
    static let claude = Color(red: 0.87, green: 0.49, blue: 0.36)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.3)
    static let green = Color(red: 0.38, green: 0.86, blue: 0.53)
    static let blue = Color(red: 0.45, green: 0.7, blue: 1.0)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.34)
}

let islandSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)

struct BlurFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 6 : 0)
            .scaleEffect(active ? 0.96 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

// MARK: - Ildiz

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicModel
    @ObservedObject var claude: ClaudeModel
    @ObservedObject var calendar: CalendarModel

    init(model: IslandModel) {
        _model = ObservedObject(wrappedValue: model)
        _music = ObservedObject(wrappedValue: model.music)
        _claude = ObservedObject(wrappedValue: model.claude)
        _calendar = ObservedObject(wrappedValue: model.calendar)
    }

    var body: some View {
        let mode = model.mode
        let g = model.geometry
        let size = g.frame(mode)
        let shape = NotchShape(top: g.topRadius(mode), bottom: g.bottomRadius(mode))
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.black
                content(mode, g)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .background(
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(mode == .expanded ? 0.5 : (mode == .peek ? 0.3 : 0)), radius: 18, x: 0, y: 8)
            )
            .contentShape(shape)
            .onTapGesture { if model.mode != .expanded { model.expand() } }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(islandSpring, value: mode)
        .animation(islandSpring, value: model.metrics)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(_ mode: IslandMode, _ g: IslandGeometry) -> some View {
        switch mode {
        case .idle:
            Color.clear
        case .live:
            LiveStrip(g: g, music: music, claude: claude).transition(.blurFade)
        case .peek:
            if let p = model.peek { PeekView(peek: p, g: g).transition(.blurFade) }
        case .expanded:
            ExpandedView(g: g, model: model, music: music, claude: claude, calendar: calendar).transition(.blurFade)
        }
    }
}

// MARK: - Yopiq holat (jonli)

struct LiveStrip: View {
    let g: IslandGeometry
    @ObservedObject var music: MusicModel
    @ObservedObject var claude: ClaudeModel

    var body: some View {
        let h = g.m.notch.height
        HStack(spacing: 0) {
            ZStack { left }.frame(width: g.slot, height: h)
            Color.clear.frame(width: g.m.notch.width, height: h)
            ZStack { right }.frame(width: g.slot, height: h)
        }
        .frame(width: g.body(.live).width, height: h)
        .animation(islandSpring, value: music.isPlaying)
        .animation(islandSpring, value: claude.primary?.state)
    }

    @ViewBuilder private var left: some View {
        if music.isPlaying {
            ArtworkView(image: music.artwork, size: g.m.notch.height - (g.m.hasNotch ? 11 : 7), corner: g.m.hasNotch ? 6 : 4.5)
                .transition(.blurFade)
        } else if let s = claude.primary {
            ClaudeGlyph(state: s.state).frame(width: 17, height: 17).transition(.blurFade)
        }
    }

    @ViewBuilder private var right: some View {
        if let s = claude.primary {
            if music.isPlaying {
                ClaudeGlyph(state: s.state).frame(width: 15, height: 15).transition(.blurFade)
            } else {
                ClaudeStatusBadge(session: s).transition(.blurFade)
            }
        } else if music.isPlaying {
            Waveform(color: music.accent, playing: true).frame(width: 18, height: 13).transition(.blurFade)
        }
    }
}

struct ClaudeStatusBadge: View {
    let session: ClaudeSession

    var body: some View {
        switch session.state {
        case .waiting:
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.amber)
                .symbolEffect(.pulse)
        case .working:
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(UzTime.timer(tl.date.timeIntervalSince(session.workStarted ?? session.updatedAt)))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.claude)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        case .done, .idle:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.green)
        }
    }
}

// MARK: - Qisqa xabar

struct PeekView: View {
    let peek: Peek
    let g: IslandGeometry

    var body: some View {
        let size = g.body(.peek)
        VStack(spacing: 0) {
            Color.clear.frame(height: g.m.notch.height)
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peek.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if !peek.subtitle.isEmpty {
                        Text(peek.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(height: IslandGeometry.peekContent - 8)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var tint: Color {
        switch peek.kind {
        case .claudeDone: Palette.green
        case .claudeWaiting: Palette.amber
        case .calendar: Palette.blue
        }
    }

    private var symbol: String {
        switch peek.kind {
        case .claudeDone: "checkmark"
        case .claudeWaiting: "hand.raised.fill"
        case .calendar: "calendar"
        }
    }
}

// MARK: - Ochiq holat

struct ExpandedView: View {
    let g: IslandGeometry
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicModel
    @ObservedObject var claude: ClaudeModel
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        let nH = g.m.notch.height
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TimelineView(.everyMinute) { tl in
                    Text(UzTime.header(tl.date))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text.opacity(0.9))
                }
                Spacer(minLength: g.m.notch.width + 24)
                HStack(spacing: 8) {
                    if claude.activeCount > 0 {
                        HStack(spacing: 5) {
                            ClaudeGlyph(state: claude.primary?.state ?? .idle).frame(width: 12, height: 12)
                            Text("\(claude.activeCount)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    Button { model.onMenu?() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 20, height: 16)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 24)
            .frame(height: nH)

            HStack(alignment: .top, spacing: 18) {
                MusicCard(music: music).frame(width: 292, alignment: .leading)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 148).padding(.top, 4)
                VStack(alignment: .leading, spacing: 12) {
                    ClaudeCard(claude: claude)
                    CalendarCard(calendar: calendar)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .frame(height: IslandGeometry.expandedContent, alignment: .top)
        }
        .frame(width: IslandGeometry.expandedWidth, height: nH + IslandGeometry.expandedContent, alignment: .top)
    }
}

// MARK: Musiqa

struct MusicCard: View {
    @ObservedObject var music: MusicModel

    var body: some View {
        let n = music.now
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(image: music.artwork, size: 104, corner: 16)
                    if let icon = music.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .offset(x: 7, y: 7)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { music.openSourceApp() }

                VStack(alignment: .leading, spacing: 3) {
                    Text(n?.title ?? "Hech narsa chalinmayapti")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    Text(subtitle(n))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    controls
                }
                .frame(height: 104)
            }
            if let n, n.duration > 0 {
                ProgressRow(music: music)
            }
        }
    }

    private func subtitle(_ n: NowPlaying?) -> String {
        guard let n else { return "Yandex Musiqani oching" }
        if !n.artist.isEmpty { return n.artist }
        return music.appName
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(action: music.previous) {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }
            Button(action: music.togglePlay) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26, height: 26)
            }
            Button(action: music.next) {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Palette.text)
        .padding(.leading, -6)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct ProgressRow: View {
    @ObservedObject var music: MusicModel
    @State private var scrub: Double?

    var body: some View {
        let n = music.now
        let dur = n?.duration ?? 0
        TimelineView(.animation(minimumInterval: 0.25, paused: !(n?.playing ?? false))) { tl in
            let pos = scrub.map { $0 * dur } ?? (n?.position(at: tl.date) ?? 0)
            let frac = dur > 0 ? min(1, max(0, pos / dur)) : 0
            HStack(spacing: 10) {
                Text(Self.fmt(pos)).frame(width: 34, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(music.accent).frame(width: max(5, geo.size.width * frac))
                    }
                    .frame(height: scrub == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in scrub = min(1, max(0, v.location.x / max(1, geo.size.width))) }
                            .onEnded { v in
                                let f = min(1, max(0, v.location.x / max(1, geo.size.width)))
                                music.seek(to: f * dur)
                                scrub = nil
                            }
                    )
                }
                .frame(height: 16)
                Text("-" + Self.fmt(max(0, dur - pos))).frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(Palette.secondary)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: scrub == nil)
    }

    static func fmt(_ t: Double) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: Claude

struct ClaudeCard: View {
    @ObservedObject var claude: ClaudeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "CLAUDE", trailing: summary)
            if claude.sessions.isEmpty {
                Text("Hozircha faol sessiya yoʻq")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiary)
                    .frame(height: 30, alignment: .leading)
            } else {
                ForEach(claude.sessions.prefix(2)) { s in SessionRow(session: s) }
            }
        }
    }

    private var summary: String {
        let w = claude.sessions.filter { $0.state == .working }.count
        let q = claude.sessions.filter { $0.state == .waiting }.count
        var parts: [String] = []
        if q > 0 { parts.append("\(q) kutmoqda") }
        if w > 0 { parts.append("\(w) ishlamoqda") }
        return parts.joined(separator: " · ")
    }
}

struct SessionRow: View {
    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 9) {
            ClaudeGlyph(state: session.state).frame(width: 15, height: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.project)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture { AppOpener.activate(bundleID: session.appBundle ?? "com.anthropic.claudefordesktop") }
    }

    private var subtitle: String {
        switch session.state {
        case .working, .waiting: return session.detail
        case .done, .idle: return session.prompt.isEmpty ? session.detail : session.prompt
        }
    }

    @ViewBuilder private var trailing: some View {
        switch session.state {
        case .working:
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(UzTime.timer(tl.date.timeIntervalSince(session.workStarted ?? session.updatedAt)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.claude)
            }
        case .waiting:
            Text("Javob kerak")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.amber))
        case .done:
            Text(doneText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.green)
        case .idle:
            EmptyView()
        }
    }

    private var doneText: String {
        if let s = session.workStarted, let e = session.workEnded {
            return "✓ " + UzTime.duration(e.timeIntervalSince(s))
        }
        return "✓"
    }
}

// MARK: Kalendar

struct CalendarCard: View {
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "KALENDAR", trailing: "")
            switch calendar.access {
            case .granted:
                if calendar.events.isEmpty {
                    Text("Bugun boshqa uchrashuv yoʻq")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                        .frame(height: 30, alignment: .leading)
                } else {
                    ForEach(calendar.events.prefix(2)) { e in EventRow(event: e, calendar: calendar) }
                }
            case .unknown, .denied:
                Button { calendar.requestOrOpenSettings() } label: {
                    Label("Kalendarga ruxsat berish", systemImage: "calendar.badge.plus")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(PillStyle(tint: Palette.blue))
                .padding(.top, 2)
            }
        }
    }
}

struct EventRow: View {
    let event: CalEvent
    let calendar: CalendarModel

    var body: some View {
        TimelineView(.everyMinute) { tl in
            HStack(spacing: 9) {
                Capsule().fill(event.color).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(timeText(tl.date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(event.isNow ? event.color : Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let url = event.meetingURL {
                    Button { AppOpener.open(url) } label: {
                        Text("Qoʻshilish").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(PillStyle(tint: event.color))
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture { calendar.openCalendarApp() }
        }
    }

    private func timeText(_ now: Date) -> String {
        let range = "\(UzTime.clock(event.start))–\(UzTime.clock(event.end))"
        if event.start <= now { return "\(range) · davom etmoqda" }
        if !Calendar.current.isDate(event.start, inSameDayAs: now) { return "Ertaga, \(range)" }
        let mins = Int(event.start.timeIntervalSince(now) / 60)
        if mins < 60 { return "\(range) · \(max(1, mins)) daq qoldi" }
        return "\(range) · \(mins / 60) soat \(mins % 60) daq qoldi"
    }
}

// MARK: - Mayda bo'laklar

struct SectionHeader: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Palette.tertiary)
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

struct PillStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.5 : 0.3)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

