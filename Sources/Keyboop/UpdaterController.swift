import AppKit
import Foundation

/// A release advertised by Keyboop's public appcast. Download URLs and update payload metadata are
/// deliberately not represented, so they cannot accidentally become part of this code path.
struct ReleaseCandidate: Equatable {
    let version: String
    let channel: String?
    let minimumSystemVersion: String?
    let hardwareRequirements: String?

    var isBeta: Bool { channel == "beta" }
}

private struct NumericVersion: Comparable, Equatable {
    let parts: [Int]

    init?(_ raw: String) {
        guard raw.range(of: #"^[0-9]+(?:\.[0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        let pieces = raw.split(separator: ".")
        let values = pieces.compactMap { Int($0) }
        guard !values.isEmpty, values.count == pieces.count else { return nil }
        parts = values
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private(set) var releases: [ReleaseCandidate] = []
    private var insideItem = false
    private var field = ""
    private var text = ""
    private var version: String?
    private var channel: String?
    private var minimumSystemVersion: String?
    private var hardwareRequirements: String?

    func parse(_ data: Data) throws -> [ReleaseCandidate] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw parser.parserError ?? MonitorError.invalidFeed }
        return releases
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = (qName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
        if name == "item" {
            insideItem = true
            version = nil; channel = nil; minimumSystemVersion = nil; hardwareRequirements = nil
        }
        guard insideItem else { return }
        field = name
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = (qName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if insideItem, name == field {
            switch name {
            case "version", "shortVersionString":
                if version == nil, NumericVersion(value) != nil { version = value }
            case "channel": channel = value.isEmpty ? nil : value
            case "minimumSystemVersion": minimumSystemVersion = value.isEmpty ? nil : value
            case "hardwareRequirements": hardwareRequirements = value.isEmpty ? nil : value
            default: break
            }
        }
        if name == "item" {
            if let version {
                releases.append(ReleaseCandidate(version: version, channel: channel,
                                                 minimumSystemVersion: minimumSystemVersion,
                                                 hardwareRequirements: hardwareRequirements))
            }
            insideItem = false
        }
        field = ""; text = ""
    }
}

private enum MonitorError: LocalizedError {
    case invalidFeed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidFeed: return L10n.t("upd.errorFeed")
        case .invalidResponse: return L10n.t("upd.errorResponse")
        }
    }
}

/// Read-only upstream release monitor.
///
/// Security boundary: this type can fetch text metadata and open a hard-coded GitHub comparison.
/// It has no update-archive request, downloader, extractor, helper, relauncher, or replacement path.
final class UpdaterController {
    static let shared = UpdaterController()

    private let feedURL = URL(string: "https://keyboop.com/appcast.xml")!
    private let repository = "iffuno/keyboop"
    private let interval: TimeInterval = 2 * 60 * 60
    private let defaults = UserDefaults.standard
    private let checksKey = "personal.upstreamChecks"
    private let seenKey = "personal.seenUpstreamVersions"
    private let lastSuccessKey = "personal.lastUpstreamCheck"
    private var timer: Timer?
    private var checking = false

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": "Keyboop-Personal/\(baselineVersion)"]
        return URLSession(configuration: config)
    }()

    private init() {}

    private var baselineVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "KeyboopUpstreamBaselineVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }

    var automaticChecks: Bool {
        get { defaults.object(forKey: checksKey) == nil ? true : defaults.bool(forKey: checksKey) }
        set {
            defaults.set(newValue, forKey: checksKey)
            schedule()
        }
    }

    static private(set) var lastFailure: (text: String, at: Date)?
    static var lastSuccessfulCheck: Date? { UserDefaults.standard.object(forKey: "personal.lastUpstreamCheck") as? Date }
    static let staleAfterDays = 7
    static var updatesLookBroken: Bool {
        guard UpdaterController.shared.automaticChecks else { return false }
        guard let last = lastSuccessfulCheck else { return lastFailure != nil }
        return Date().timeIntervalSince(last) > Double(staleAfterDays) * 86_400
    }

    func start() {
        schedule()
        guard automaticChecks else { return }
        let last = Self.lastSuccessfulCheck ?? .distantPast
        let delay: TimeInterval = Date().timeIntervalSince(last) >= interval ? 25 : interval
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.automaticChecks == true else { return }
            self?.check(manual: false)
        }
        kbLog("upstream monitor: started (check=\(automaticChecks), beta=\(AppSettings.shared.betaChannel), baseline=\(baselineVersion))")
    }

    func checkNow() {
        NSApp.activate(ignoringOtherApps: true)
        check(manual: true)
    }

    func noteChannelChanged() {
        kbLog("upstream monitor: beta = \(AppSettings.shared.betaChannel)")
        if AppSettings.shared.betaChannel { check(manual: false) }
    }

    private func schedule() {
        timer?.invalidate(); timer = nil
        guard automaticChecks else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.check(manual: false) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check(manual: Bool) {
        guard !checking else {
            if manual {
                Task { @MainActor in
                    self.showInfo(title: L10n.t("upd.checking"), body: "")
                }
            }
            return
        }
        checking = true
        kbLog("upstream monitor: \(manual ? "manual" : "scheduled") check")
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.checking = false } }
            do {
                let candidates = try await fetchCandidates()
                let result = try await newestReviewable(in: candidates, manual: manual)
                await MainActor.run {
                    self.noteSuccess()
                    self.present(result: result, manual: manual)
                }
            } catch {
                await MainActor.run { self.noteFailure(error, manual: manual) }
            }
        }
    }

    private func fetchCandidates() async throws -> [ReleaseCandidate] {
        var request = URLRequest(url: feedURL)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw MonitorError.invalidResponse }
        let parsed = try AppcastParser().parse(data)
        guard !parsed.isEmpty, let baseline = NumericVersion(baselineVersion) else { throw MonitorError.invalidFeed }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let system = NumericVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")!
        return parsed.filter { item in
            guard let version = NumericVersion(item.version), version > baseline else { return false }
            if item.isBeta && !AppSettings.shared.betaChannel { return false }
            if let minimum = item.minimumSystemVersion, let minVersion = NumericVersion(minimum), system < minVersion { return false }
            if let hardware = item.hardwareRequirements, !hardware.isEmpty, hardware != "arm64" { return false }
            return true
        }.sorted { NumericVersion($0.version)! > NumericVersion($1.version)! }
    }

    private enum ReviewResult { case release(ReleaseCandidate), sourcePending(ReleaseCandidate?), none }

    private func newestReviewable(in candidates: [ReleaseCandidate], manual: Bool) async throws -> ReviewResult {
        guard let newest = candidates.first else { return .none }
        if !manual, seenVersions.contains(newest.version) { return .none }
        for candidate in candidates {
            if try await publicTagExists(candidate.version) { return .release(candidate) }
        }
        return .sourcePending(newest)
    }

    private func publicTagExists(_ version: String) async throws -> Bool {
        guard NumericVersion(version) != nil,
              let url = URL(string: "https://api.github.com/repos/\(repository)/git/ref/tags/v\(version)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MonitorError.invalidResponse }
        if http.statusCode == 200 { return true }
        if http.statusCode == 404 { return false }
        throw MonitorError.invalidResponse
    }

    @MainActor private func present(result: ReviewResult, manual: Bool) {
        switch result {
        case .release(let release): showRelease(release)
        case .sourcePending(let release):
            guard manual else {
                if let release { kbLog("upstream monitor: \(release.version) announced, public source tag missing") }
                return
            }
            showInfo(title: String(format: L10n.t("upd.sourcePendingTitle"), release?.version ?? "?"),
                     body: L10n.t("upd.sourcePendingBody"))
        case .none:
            if manual { showInfo(title: L10n.t("upd.currentTitle"), body: L10n.t("upd.currentBody")) }
        }
    }

    @MainActor private func showRelease(_ release: ReleaseCandidate) {
        let kind = release.isBeta ? L10n.t("upd.kindBeta") : L10n.t("upd.kindStable")
        // Scheduled checks show each exact version once. Manual checks deliberately bypass this
        // marker, so the user can reopen the comparison whenever they choose.
        markSeen(release.version)
        AppBanner.shared.show(
            title: String(format: L10n.t("upd.notifyTitle"), release.version),
            body: String(format: L10n.t("upd.notifyBody"), kind),
            actions: [.init(title: L10n.t("upd.review"), coral: true) { [weak self] in
                self?.openComparison(to: release.version)
            }]
        )
    }

    @MainActor private func showInfo(title: String, body: String) {
        AppBanner.shared.show(title: title, body: body, autoDismiss: 7)
    }

    @MainActor private func openComparison(to version: String) {
        guard NumericVersion(baselineVersion) != nil, NumericVersion(version) != nil,
              let url = URL(string: "https://github.com/\(repository)/compare/v\(baselineVersion)...v\(version)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var seenVersions: Set<String> { Set(defaults.stringArray(forKey: seenKey) ?? []) }

    private func markSeen(_ version: String) {
        guard NumericVersion(version) != nil else { return }
        var seen = seenVersions
        seen.insert(version)
        defaults.set(Array(seen).sorted(), forKey: seenKey)
        kbLog("upstream monitor: v\(version) marked reviewed/notified")
    }

    @MainActor private func noteSuccess() {
        defaults.set(Date(), forKey: lastSuccessKey)
        Self.lastFailure = nil
        NotificationCenter.default.post(name: .updaterStatusChanged, object: nil)
    }

    @MainActor private func noteFailure(_ error: Error, manual: Bool) {
        let text = error.localizedDescription
        kbLog("upstream monitor: check failed — \(text)")
        Self.lastFailure = (text, Date())
        NotificationCenter.default.post(name: .updaterStatusChanged, object: nil)
        if manual { showInfo(title: L10n.t("upd.problem"), body: text) }
    }
}
