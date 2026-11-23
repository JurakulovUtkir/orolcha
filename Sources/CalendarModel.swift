import AppKit
import EventKit
import SwiftUI

struct CalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let meetingURL: URL?

    var isNow: Bool { start <= Date() && end > Date() }
}

/// macOS Kalendar (iCloud, Google — Internet Accounts orqali qo'shilganlari ham).
final class CalendarModel: ObservableObject {
    enum Access: Equatable { case unknown, granted, denied }

    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var access: Access = .unknown
    var onSoon: ((CalEvent) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: Any?
    private var notified = Set<String>()

    func start() {
        updateAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        if access == .unknown { requestAccess() } else { reload() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.reload() }
    }

    func demoSet(_ list: [CalEvent]) {
        events = list
        access = .granted
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAccess()
                self?.reload()
            }
        }
    }

    func requestOrOpenSettings() {
        if access == .unknown {
            requestAccess()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            AppOpener.open(url)
        }
    }

    func openCalendarApp() {
        AppOpener.activate(bundleID: "com.apple.iCal")
    }

    private func updateAccess() {
        let st = EKEventStore.authorizationStatus(for: .event)
        let a: Access
        switch st {
        case .fullAccess: a = .granted
        case .notDetermined: a = .unknown
        default: a = .denied
        }
        if a != access { access = a }
    }

    func reload() {
        updateAccess()
        guard access == .granted else { return }
        let now = Date()
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) else { return }
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600), end: end, calendars: nil)
        let list = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)
            .map(Self.make)
        if Array(list) != events { events = Array(list) }
        for e in events where !notified.contains(e.id) {
            let dt = e.start.timeIntervalSince(now)
            if dt > 0 && dt <= 5 * 60 {
                notified.insert(e.id)
                onSoon?(e)
            }
        }
    }

    private static let linkRegex = try? NSRegularExpression(
        pattern: #"https?://[^\s<>"']*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|telemost\.yandex\.[a-z]+|webex\.com)[^\s<>"']*"#,
        options: [.caseInsensitive])

    private static func make(_ e: EKEvent) -> CalEvent {
        let text = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        var link: URL?
        if let re = linkRegex,
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range, in: text) {
            link = URL(string: String(text[r]))
        }
        let base = e.eventIdentifier ?? e.calendarItemIdentifier
        return CalEvent(
            id: "\(base)-\(Int(e.startDate.timeIntervalSince1970))",
            title: (e.title?.isEmpty == false ? e.title! : "Nomsiz uchrashuv"),
            start: e.startDate,
            end: e.endDate,
            color: Color(nsColor: e.calendar?.color ?? .systemBlue),
            meetingURL: link
        )
    }
}
