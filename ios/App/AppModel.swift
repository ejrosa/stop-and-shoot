import Foundation
import Network
import SwiftUI
import UIKit
import StopAndShootLogic

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var pins: [Pin] = []
    @Published var gpsLine = "Location not set"
    @Published var lastSpeech: String?
    @Published var notice: String?
    @Published var isMarking = false
    @Published var importing = false
    @Published var shareFile: ShareFile?
    @Published var safetyAcknowledged: Bool
    @Published var lookupsEnabled: Bool {
        didSet { UserDefaults.standard.set(lookupsEnabled, forKey: Keys.lookups) }
    }
    @Published var dictationExplained: Bool

    private let store: PinStore
    private let location = LocationService()
    private let speaker = SpeechService()
    private let gate = MarkGate()
    private let monitor = NWPathMonitor()
    private var online = false
    private var sceneIsActive = false
    private var enriching: Set<String> = []

    private enum Keys {
        static let safety = "sas.ios.safetyOK"
        static let lookups = "sas.ios.lookupsEnabled"
        static let dictation = "sas.ios.dictationExplained"
    }

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StopAndShoot", isDirectory: true)
        store = PinStore(directory: directory)
        pins = store.load().sorted { $0.ts == $1.ts ? $0.id > $1.id : $0.ts > $1.ts }
        safetyAcknowledged = UserDefaults.standard.bool(forKey: Keys.safety)
        let storedLookups = UserDefaults.standard.object(forKey: Keys.lookups) as? Bool
        lookupsEnabled = StopAndShootLogic.lookupsEnabled(stored: storedLookups)
        dictationExplained = UserDefaults.standard.bool(forKey: Keys.dictation)
        location.onChange = { [weak self] in
            self?.gpsLine = self?.location.gpsLine() ?? "Waiting for GPS"
        }
        gpsLine = location.gpsLine()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.setOnline(connected)
            }
        }
        monitor.start(queue: DispatchQueue(label: "stopandshoot.network"))
    }

    func setSceneActive(_ active: Bool) {
        sceneIsActive = active
        location.setWantsUpdates(active)
        gpsLine = location.gpsLine()
    }

    func acknowledgeSafety() {
        safetyAcknowledged = true
        UserDefaults.standard.set(true, forKey: Keys.safety)
        location.requestPermission()
    }

    func explainDictation() {
        dictationExplained = true
        UserDefaults.standard.set(true, forKey: Keys.dictation)
    }

    func pin(_ id: String) -> Pin? { pins.first { $0.id == id } }

    func markSpot(note: String?, tags: [String], announceInApp: Bool) async -> String {
        if let speech = await gate.run({
            await self.performMark(note: note, tags: tags, announceInApp: announceInApp)
        }) {
            return speech
        }
        announce(Speech.busy, inApp: announceInApp)
        return Speech.busy
    }

    func handle(url: URL) {
        guard let link = parseMarkLink(url) else { return }
        Task { await markSpot(note: link.note, tags: link.tags, announceInApp: true) }
    }

    func updatePin(_ id: String, _ mutate: (inout Pin) -> Void) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        var copy = pins
        mutate(&copy[index])
        do {
            try store.save(copy)
            pins = copy
        } catch {
            notice = "Couldn't write the spot list."
        }
    }

    func delete(id: String) {
        let copy = pins.filter { $0.id != id }
        do {
            try store.save(copy)
            pins = copy
            notice = "Deleted"
        } catch {
            notice = "Couldn't write the spot list."
        }
    }

    func enrichIfNeeded(id: String) {
        guard let pin = pin(id) else { return }
        let status = pin.nearby?.status
        if status == nil || (status == "offline" && online) {
            Task { await enrich(id: id, force: false) }
        }
    }

    func enrich(id: String, force: Bool) async {
        guard !enriching.contains(id), let starting = pin(id) else { return }
        enriching.insert(id)
        defer { enriching.remove(id) }
        let key = nrelKey()
        _ = await StopAndShootLogic.enrich(
            pin: starting,
            force: force,
            online: online,
            lookupsEnabled: lookupsEnabled,
            apiKey: key,
            client: URLSessionHTTP(),
            onUpdate: { [weak self] updated in
                guard let self else { return }
                await self.applyEnrichment(updated)
            }
        )
    }

    func export(_ kind: ExportKind) {
        let now = Date()
        let ext: String
        let body: Data
        switch kind {
        case .json:
            ext = "json"
            guard let data = try? exportJSON(pins: pins, appName: AppIdentity.name, exportedAt: now) else {
                notice = "Couldn't create the export file."
                return
            }
            body = data
        case .csv:
            ext = "csv"
            body = Data(exportCSV(pins: pins).utf8)
        case .gpx:
            ext = "gpx"
            body = Data(exportGPX(pins: pins, appName: AppIdentity.name).utf8)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName(extension: ext, now: now))
        do {
            try body.write(to: url, options: .atomic)
            shareFile = ShareFile(url: url)
        } catch {
            notice = "Couldn't create the export file."
        }
    }

    func importFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            notice = "That file isn't a spots backup"
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                notice = "That file isn't a spots backup"
                return
            }
            importData(data)
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func speakParked(_ text: String) {
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
        } else {
            speaker.speak(text)
        }
    }

    private func importData(_ data: Data) {
        do {
            let result = try StopAndShootLogic.importPins(existing: pins, data: data)
            try store.save(result.pins)
            pins = result.pins.sorted { $0.ts == $1.ts ? $0.id > $1.id : $0.ts > $1.ts }
            notice = "Imported \(result.added) spot\(result.added == 1 ? "" : "s")"
        } catch {
            notice = "That file isn't a spots backup"
        }
    }

    private func performMark(note: String?, tags: [String], announceInApp: Bool) async -> String {
        isMarking = true
        defer { isMarking = false }
        location.setWantsUpdates(true)
        defer { location.setWantsUpdates(sceneIsActive) }
        let fix: LocationFix
        do {
            fix = try await location.currentFix(maxAge: MarkingPolicy.freshFixMaxAge)
        } catch let error as MarkFailure {
            let speech = Speech.failed(error)
            announce(speech, inApp: announceInApp)
            return speech
        } catch {
            let speech = Speech.failed(.timedOut)
            announce(speech, inApp: announceInApp)
            return speech
        }
        guard case .success(let pin) = makePin(id: UUID().uuidString, fix: fix, note: note, tags: tags, now: Date()) else {
            let speech = Speech.failed(.invalidFix)
            announce(speech, inApp: announceInApp)
            return speech
        }
        var next = pins
        next.insert(pin, at: 0)
        do {
            try store.save(next)
        } catch {
            announce(Speech.storageFailed, inApp: announceInApp)
            return Speech.storageFailed
        }
        pins = next
        let speech = Speech.saved(pin: pin, locale: .current, timeZone: .current)
        announce(speech, inApp: announceInApp)
        let id = pin.id
        Task { await self.enrich(id: id, force: false) }
        return speech
    }

    private func announce(_ speech: String, inApp: Bool) {
        lastSpeech = speech
        guard inApp else { return }
        speakParked(speech)
        let generator = UINotificationFeedbackGenerator()
        if speech == Speech.busy || speech.hasPrefix("Couldn't") {
            generator.notificationOccurred(.warning)
        } else {
            generator.notificationOccurred(.success)
        }
    }

    private func applyEnrichment(_ updated: Pin) {
        guard let index = pins.firstIndex(where: { $0.id == updated.id }) else { return }
        var merged = pins[index]
        let typedName = merged.name
        merged.place = updated.place
        merged.weather = updated.weather
        merged.nearby = updated.nearby
        if typedName.isEmpty { merged.name = updated.name }
        do {
            try store.save(pinsReplacing(index, with: merged))
            pins[index] = merged
        } catch {
            notice = "Couldn't write the spot list."
        }
    }

    private func pinsReplacing(_ index: Int, with pin: Pin) -> [Pin] {
        var copy = pins
        copy[index] = pin
        return copy
    }

    private func setOnline(_ connected: Bool) {
        let was = online
        online = connected
        guard connected, !was else { return }
        for pin in pins {
            let status = pin.nearby?.status
            if status == nil || status == "offline" || status == "error" {
                Task { await enrich(id: pin.id, force: false) }
            }
        }
    }

    private func nrelKey() -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "NRELAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.contains("$(") { return ServiceEndpoints.nrelDemoAPIKey }
        return raw
    }
}

enum ExportKind {
    case json, csv, gpx
}

struct URLSessionHTTP: HTTPFetching {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func send(_ request: HTTPRequest) async throws -> Data {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpBody = request.body.flatMap { Data($0.utf8) }
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSessionHTTP.session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FetchFailure.badStatus
        }
        return data
    }
}
