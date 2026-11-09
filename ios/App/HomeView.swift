import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.safetyAcknowledged {
                VStack(alignment: .leading, spacing: 8) {
                    Text(TravelCopy.driveSafe)
                    Text(TravelCopy.locationUse)
                    Text(TravelCopy.lookupShort)
                    Button("Continue") { model.acknowledgeSafety() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
            Button {
                Task { await model.markSpot(note: nil, tags: [], announceInApp: true) }
            } label: {
                VStack(spacing: 4) {
                    Text(model.isMarking ? "Getting GPS…" : "Mark this spot")
                        .font(.title2.weight(.semibold))
                    Text("Saves coordinates, time, and accuracy")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(Theme.orange, in: RoundedRectangle(cornerRadius: 20))
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(model.isMarking)
            .accessibilityIdentifier("markButton")
            .accessibilityLabel(model.isMarking ? "Getting GPS" : "Mark this spot")
            .accessibilityHint("Saves the current location, time, and accuracy, then speaks the result.")

            Text(model.gpsLine)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .accessibilityLabel(model.gpsLine)
            if model.gpsLine == "Location off" {
                Button("Open Settings") { model.openSettings() }
            }
            if let speech = model.lastSpeech {
                Text(speech)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(speech.hasPrefix("Couldn't") || speech == Speech.busy ? Theme.warn : .white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text("Saved spots (\(model.pins.count))")
                        .font(.headline)
                    if model.pins.isEmpty {
                        Text("No spots yet. When you are parked, tap the button, or ask Siri to mark a spot in Stop and Shoot.")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(model.pins) { pin in
                        NavigationLink(value: Route.pin(pin.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pin.name.isEmpty ? "Saved spot" : pin.name)
                                    .font(.headline)
                                Text(Date(timeIntervalSince1970: pin.ts / 1000).formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                if let acc = pin.acc {
                                    Text("±\(Int(acc.rounded())) m")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    if let notice = model.notice {
                        Text(notice).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Stop & Shoot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.help) {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Setup and privacy")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Export JSON") { model.export(.json) }
                    Button("Export GPX") { model.export(.gpx) }
                    Button("Export CSV") { model.export(.csv) }
                    Button("Import JSON") { model.importing = true }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Backup and import")
            }
        }
    }
}
