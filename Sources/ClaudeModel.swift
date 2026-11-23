import AppKit
import Network

struct ClaudeSession: Identifiable, Equatable {
    enum State: Equatable { case working, waiting, done, idle }

    let id: String
    var project: String
    var state: State
    var detail: String
    var prompt: String
    var updatedAt: Date
    var workStarted: Date?
    var workEnded: Date?
    var appBundle: String?
}

enum ClaudeEvent {
    case finished(ClaudeSession)
    case waiting(ClaudeSession)
}

/// Claude Code hook'laridan (curl → 127.0.0.1:47811) sessiya holatlarini yig'adi.
final class ClaudeModel: ObservableObject {
    static let port: UInt16 = 47811

    @Published private(set) var sessions: [ClaudeSession] = []
    var onEvent: ((ClaudeEvent) -> Void)?

    private let server = HookServer(port: ClaudeModel.port)
    private var sweepTimer: Timer?

    var hasActive: Bool { sessions.contains { $0.state == .working || $0.state == .waiting } }
    var activeCount: Int { sessions.filter { $0.state == .working || $0.state == .waiting }.count }
    /// Eng muhim sessiya: avval javob kutayotgani, keyin ishlayotgani.
    var primary: ClaudeSession? {
        sessions.first { $0.state == .waiting } ?? sessions.first { $0.state == .working }
    }

    func start(state: @escaping () -> [String: Any]) {
        server.stateProvider = state
        server.onRequest = { [weak self] json, headers in
            DispatchQueue.main.async { self?.handle(json, headers) }
        }
        server.start()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sweep() }
    }

    func demoSet(_ list: [ClaudeSession]) { sessions = list }

    private func handle(_ j: [String: Any], _ h: [String: String]) {
        guard let sid = j["session_id"] as? String, let event = j["hook_event_name"] as? String else { return }
        if event == "SessionEnd" {
            sessions.removeAll { $0.id == sid }
            return
        }
        let cwd = (j["cwd"] as? String) ?? ""
        var s = sessions.first { $0.id == sid }
            ?? ClaudeSession(id: sid, project: Self.projectName(cwd), state: .idle, detail: "Tayyor", prompt: "",
                             updatedAt: Date(), workStarted: nil, workEnded: nil, appBundle: nil)
        if !cwd.isEmpty { s.project = Self.projectName(cwd) }
        if let app = h["x-app"], !app.isEmpty { s.appBundle = app }
        s.updatedAt = Date()

        var fire: ClaudeEvent?
        switch event {
        case "UserPromptSubmit":
            s.state = .working
            s.workStarted = Date()
            s.workEnded = nil
            s.prompt = Self.firstLine((j["prompt"] as? String) ?? "", max: 90)
            s.detail = "Oʻylamoqda…"
        case "PreToolUse":
            if s.state != .working { s.state = .working }
            if s.workStarted == nil { s.workStarted = Date() }
            s.detail = Self.describeTool((j["tool_name"] as? String) ?? "", (j["tool_input"] as? [String: Any]) ?? [:])
        case "PostToolUse":
            if s.state != .working { s.state = .working }
            if s.workStarted == nil { s.workStarted = Date() }
        case "PreCompact":
            s.state = .working
            s.detail = "Kontekst ixchamlanmoqda"
        case "Notification":
            let msg = (j["message"] as? String) ?? ""
            let type = (j["notification_type"] as? String) ?? ""
            let idle = type == "idle_prompt" || msg.lowercased().contains("waiting for your input")
            if !idle {
                s.state = .waiting
                s.detail = Self.translate(msg)
                fire = .waiting(s)
            }
        case "Stop":
            s.state = .done
            s.workEnded = Date()
            s.detail = "Tugadi"
            fire = .finished(s)
        default:
            break
        }
        upsert(s)
        if let fire { onEvent?(fire) }
    }

    private func upsert(_ s: ClaudeSession) {
        var list = sessions
        if let i = list.firstIndex(where: { $0.id == s.id }) { list[i] = s } else { list.append(s) }
        func rank(_ st: ClaudeSession.State) -> Int {
            switch st { case .waiting: return 0; case .working: return 1; case .done: return 2; case .idle: return 3 }
        }
        list.sort {
            let a = rank($0.state), b = rank($1.state)
            if a != b { return a < b }
            return ($0.workStarted ?? $0.updatedAt) > ($1.workStarted ?? $1.updatedAt)
        }
        if list != sessions { sessions = list }
    }

    /// Eski sessiyalarni tozalash; uzoq jim turgan "ishlamoqda" — to'xtatilgan deb hisoblanadi.
    private func sweep() {
        let now = Date()
        var list = sessions
        list.removeAll { ($0.state == .done || $0.state == .idle) && now.timeIntervalSince($0.updatedAt) > 30 * 60 }
        for i in list.indices where list[i].state == .working && now.timeIntervalSince(list[i].updatedAt) > 12 * 60 {
            list[i].state = .idle
            list[i].detail = "Toʻxtatildi"
        }
        if list != sessions { sessions = list }
    }

    // MARK: Matnlar

    static func projectName(_ cwd: String) -> String {
        guard !cwd.isEmpty else { return "Claude" }
        if let r = cwd.range(of: "/.claude/worktrees/") {
            return URL(fileURLWithPath: String(cwd[..<r.lowerBound])).lastPathComponent
        }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    static func firstLine(_ s: String, max: Int) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count > max ? String(line.prefix(max - 1)) + "…" : line
    }

    static func describeTool(_ name: String, _ input: [String: Any]) -> String {
        func file(_ key: String) -> String {
            URL(fileURLWithPath: (input[key] as? String) ?? "").lastPathComponent
        }
        switch name {
        case "Bash":
            let d = (input["description"] as? String) ?? (input["command"] as? String) ?? ""
            return "Terminal: " + firstLine(d, max: 60)
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return "Tahrirlamoqda: " + file("file_path")
        case "Read":
            return "Oʻqimoqda: " + file("file_path")
        case "Grep", "Glob":
            return "Kod ichida qidirmoqda"
        case "WebFetch", "WebSearch":
            return "Internetda qidirmoqda"
        case "Task", "Agent":
            return "Agent: " + firstLine((input["description"] as? String) ?? "", max: 50)
        case "TodoWrite":
            return "Reja tuzmoqda"
        default:
            if name.hasPrefix("mcp__") {
                return "MCP: " + (name.components(separatedBy: "__").last ?? name)
            }
            return name
        }
    }

    static func translate(_ msg: String) -> String {
        if let r = msg.range(of: "permission to use ") {
            return "Ruxsat kerak: " + msg[r.upperBound...]
        }
        if msg.isEmpty { return "Sizning javobingiz kerak" }
        return msg
    }
}

/// Juda kichik HTTP qabul qiluvchi (faqat 127.0.0.1).
final class HookServer {
    let port: UInt16
    var onRequest: (([String: Any], [String: String]) -> Void)?
    /// GET /state — tekshiruv uchun joriy holat (asosiy oqimda yig'iladi).
    var stateProvider: (() -> [String: Any])?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "orolcha.hooks")

    init(port: UInt16) { self.port = port }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        guard let l = try? NWListener(using: params) else { retry(); return }
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.listener?.cancel(); self?.retry() }
        }
        listener = l
        l.start(queue: queue)
    }

    private func retry() {
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.start() }
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, Data())
    }

    private func receive(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            var buf = buffer
            if let data { buf.append(data) }
            if let (requestLine, headers, body) = Self.parse(buf) {
                if requestLine.hasPrefix("GET /state") {
                    var state: [String: Any] = [:]
                    if let provider = self?.stateProvider { DispatchQueue.main.sync { state = provider() } }
                    let json = (try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])) ?? Data()
                    var reply = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: \(json.count)\r\n\r\n".utf8)
                    reply.append(json)
                    c.send(content: reply, completion: .contentProcessed { _ in c.cancel() })
                    return
                }
                let reply = "HTTP/1.1 204 No Content\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                c.send(content: reply.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
                if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    self?.onRequest?(json, headers)
                }
            } else if done || error != nil || buf.count > 8_000_000 {
                c.cancel()
            } else {
                self?.receive(c, buf)
            }
        }
    }

    private static func parse(_ buf: Data) -> (String, [String: String], Data)? {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buf[buf.startIndex..<sep.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[line[..<i].lowercased().trimmingCharacters(in: .whitespaces)] =
                line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let start = sep.upperBound
        guard buf.endIndex - start >= length else { return nil }
        return (lines.first ?? "", headers, buf.subdata(in: start..<(start + length)))
    }
}
