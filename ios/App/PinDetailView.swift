import SwiftUI
import UIKit

struct PinDetailView: View {
    @ObservedObject var model: AppModel
    let pinID: String
    @StateObject private var dictation = DictationController()
    @State private var confirmDelete = false
    @State private var explainDictation = false
    @State private var pendingField: DictationField?
    @Environment(\.dismiss) private var dismiss

    private enum DictationField { case note, parking }

    private var pin: Pin? { model.pin(pinID) }

    var body: some View {
        Group {
            if let pin {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(pin)
                        tags(pin)
                        note(pin)
                        parking(pin)
                        light(pin)
                        nearby(pin)
                        actions(pin)
                    }
                    .padding(16)
                }
            } else {
                Text("This spot is no longer on this phone.")
                    .padding()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(pin?.name.isEmpty == false ? pin?.name ?? "Spot" : "Spot")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.enrichIfNeeded(id: pinID) }
        .onDisappear { dictation.stop() }
        .confirmationDialog("Delete this spot?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete spot", role: .destructive) {
                model.delete(id: pinID)
                dismiss()
            }
            Button("Keep", role: .cancel) {}
        }
        .confirmationDialog("Dictate on this iPhone?", isPresented: $explainDictation, titleVisibility: .visible) {
            Button("Dictate") {
                model.explainDictation()
                if let pendingField { start(pendingField) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("The microphone turns on only after you tap Speak, and only for this note. On-device recognition is used when this iPhone supports it. Otherwise, type the note.")
        }
    }

    private func header(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pull over before typing or dictating.")
                .font(.subheadline)
                .foregroundStyle(Theme.warn)
            TextField("Name", text: binding(\.name))
                .font(.title2.weight(.semibold))
            Text(Date(timeIntervalSince1970: pin.ts / 1000).formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(Theme.muted)
            Text(coordinateLine(pin: pin) + (pin.acc.map { " · ±\(Int($0.rounded())) m" } ?? ""))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            if let fixTs = pin.fixTs {
                Text("GPS sample \(Date(timeIntervalSince1970: fixTs / 1000).formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            HStack {
                if let url = appleMapsDirections(lat: pin.lat, lon: pin.lon, label: pin.name) {
                    Link("Navigate here", destination: url)
                }
                if let url = appleMapsView(lat: pin.lat, lon: pin.lon, label: pin.name) {
                    Link("Open in Maps", destination: url)
                }
                ShareLink(item: shareText(pin: pin)) { Text("Share") }
            }
        }
        .card()
    }

    private func tags(_ pin: Pin) -> some View {
        let extras = pin.tags.filter { !knownTags.contains($0) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.headline)
            FlowTags(tags: knownTags + extras, selected: pin.tags) { tag in
                model.updatePin(pinID) { pin in
                    if pin.tags.contains(tag) { pin.tags.removeAll { $0 == tag } }
                    else { pin.tags.append(tag) }
                }
            }
        }
        .card()
    }

    private func note(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note").font(.headline)
            TextEditor(text: binding(\.note))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
            speakButton("Speak note", field: .note)
        }
        .card()
    }

    private func parking(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parking and cautions").font(.headline)
            Text(TravelCopy.parkingDisclaimer).font(.subheadline)
            TextEditor(text: binding(\.parking))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
            speakButton("Speak parking or cautions", field: .parking)
            Text("Nearby parking in OpenStreetMap").font(.subheadline.weight(.semibold))
            if pin.nearby?.sources.contains(SourceName.overpass) == true {
                poiList(pin.nearby?.parking ?? [], empty: "No mapped parking lots within about half a mile.")
            } else {
                Text(pin.nearby?.status == "loading" ? "Loading…" : "Not loaded. This needs the OpenStreetMap Overpass service. Tap Refresh.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Text("Be aware right now").font(.subheadline.weight(.semibold))
            let lines = cautions(now: Date(), sun: sunTimes(date: Date(), lat: pin.lat, lon: pin.lon), weather: pin.weather, accuracyMeters: pin.acc, timeZone: .current, locale: .current)
            if lines.isEmpty {
                Text("Nothing flagged from weather, light, or GPS.").foregroundStyle(Theme.muted)
            } else {
                ForEach(lines, id: \.self) { Text("• \($0)") }
            }
            Text("Every stop").font(.subheadline.weight(.semibold))
            ForEach(TravelCopy.everyStop, id: \.self) { Text("• \($0)").font(.subheadline) }
        }
        .card()
    }

    private func light(_ pin: Pin) -> some View {
        let sun = sunTimes(date: Date(), lat: pin.lat, lon: pin.lon)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Light for photos").font(.headline)
            if let weather = pin.weather {
                Text(weatherLine(weather))
            } else {
                Text("Weather loads when you are online and lookups are on.").foregroundStyle(Theme.muted)
            }
            Text("Sunrise \(hm(sun.sunrise)) · golden hour until \(hm(sun.goldenMorningEnd))")
            Text("Golden hour from \(hm(sun.goldenEveningStart)) · sunset \(hm(sun.sunset))")
            Text("Blue hour \(hm(sun.blueMorningStart))–\(hm(sun.blueMorningEnd)) and \(hm(sun.blueEveningStart))–\(hm(sun.blueEveningEnd))")
            Text("Times for today at this spot, in this phone's time zone. Calculated on the phone.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func nearby(_ pin: Pin) -> some View {
        let status = pin.nearby?.status
        return VStack(alignment: .leading, spacing: 8) {
            Text("Nearby").font(.headline)
            Text("Looking up nearby places sends this spot's coordinates to the services named on each result.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            statusText(status)
            if status == "ok" || !(pin.nearby?.ev ?? []).isEmpty {
                Text("EV charging").font(.subheadline.weight(.semibold))
                poiList(pin.nearby?.ev ?? [], empty: "None found within the search distance.")
            }
            if status == "ok" {
                Text("Gas").font(.subheadline.weight(.semibold))
                poiList(pin.nearby?.fuel ?? [], empty: "None found nearby.")
                Text("Restroom").font(.subheadline.weight(.semibold))
                poiList(pin.nearby?.wc ?? [], empty: "No public restroom mapped nearby.")
            }
            if status == "ok" {
                Text("From \((pin.nearby?.sources ?? []).joined(separator: ", ")). Hours and access aren't guaranteed.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                if let errors = pin.nearby?.errors, !errors.isEmpty {
                    Text("Didn't respond: \(errors.joined(separator: "; ")).")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Button(status == "error" || status == "offline" ? "Retry" : "Refresh") {
                Task { await model.enrich(id: pinID, force: true) }
            }
            .disabled(status == "loading")
        }
        .card()
    }

    private func actions(_ pin: Pin) -> some View {
        HStack {
            Button("Copy coordinates") {
                UIPasteboard.general.string = coordinateLine(pin: pin)
                model.notice = "Copied"
            }
            Button("Delete spot", role: .destructive) { confirmDelete = true }
        }
        .card()
    }

    private func statusText(_ status: String?) -> some View {
        let text: String
        switch status {
        case "loading": text = "Looking up nearby places…"
        case "offline": text = "You're offline. The spot is saved. Nearby info waits until you reconnect."
        case "error": text = "Couldn't load nearby places. The spot is still saved."
        case "off": text = "Nearby lookup is off. The spot is saved on this phone. You can turn lookups on in Setup."
        default: text = ""
        }
        return Text(text).font(.subheadline).foregroundStyle(Theme.warn)
    }

    private func poiList(_ items: [POI], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text(empty).foregroundStyle(Theme.muted).font(.subheadline)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline)
                    Text(String(format: "%.1f mi", locale: Locale(identifier: "en_US_POSIX"), item.mi) + (item.addr.isEmpty ? "" : " · \(item.addr)"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    if !item.facts.isEmpty {
                        Text(item.facts.joined(separator: " · ")).font(.caption)
                    }
                    Text("Source: \(item.src)").font(.caption).foregroundStyle(Theme.muted)
                    if let url = appleMapsDirections(lat: item.lat, lon: item.lon, label: item.name) {
                        Link("Navigate", destination: url)
                    }
                }
            }
        }
    }

    private func speakButton(_ title: String, field: DictationField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(dictation.isListening && pendingField == field ? "Stop dictation" : title) {
                guard model.dictationExplained else {
                    pendingField = field
                    explainDictation = true
                    return
                }
                start(field)
            }
            if let message = dictation.message, pendingField == field {
                Text(message).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func start(_ field: DictationField) {
        pendingField = field
        if dictation.isListening { dictation.stop() }
        let current = field == .note ? (pin?.note ?? "") : (pin?.parking ?? "")
        dictation.toggle(current: current, onText: { text in
            model.updatePin(pinID) { pin in
                if field == .note { pin.note = text } else { pin.parking = text }
            }
        }, onStop: { text in
            model.updatePin(pinID) { pin in
                if field == .note { pin.note = text } else { pin.parking = text }
            }
            model.speakParked(field == .note ? "Note saved" : "Saved")
        })
    }

    private func binding(_ keyPath: WritableKeyPath<Pin, String>) -> Binding<String> {
        Binding(
            get: { model.pin(pinID)?[keyPath: keyPath] ?? "" },
            set: { newValue in model.updatePin(pinID) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func hm(_ date: Date?) -> String {
        guard let date else { return "—" }
        return shortTime(date, locale: .current, timeZone: .current)
    }
}

private struct FlowTags: View {
    let tags: [String]
    let selected: [String]
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Button(tag) { toggle(tag) }
                    .buttonStyle(.borderedProminent)
                    .tint(selected.contains(tag) ? Theme.orange : Color(white: 0.35))
            }
        }
    }
}

private extension View {
    func card() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
