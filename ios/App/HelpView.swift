import SwiftUI
import UIKit

struct HelpView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Safety") {
                    Text(TravelCopy.driveSafe)
                }
                section("Siri") {
                    Text("After location is allowed, you can say:")
                    Text("“Mark spot in Stop & Shoot”")
                    Text("“Mark a spot with Stop & Shoot”")
                    Text("“Save this spot in Stop & Shoot”")
                    Text("Siri uses the app name, which may sound like “Stop and Shoot.” If a phrase does not trigger, open Shortcuts and add the Mark Spot action to a shortcut you name yourself.")
                    Text(TravelCopy.siriLimits)
                    Text(TravelCopy.noGrok)
                    Text("A link from Shortcuts can also open the app and mark a spot: stopandshoot://mark")
                    Text("That link does not accept coordinates. The pin always comes from this phone's GPS. An optional note uses stopandshoot://mark?note= followed by the words.")
                    Button("Copy mark link") {
                        UIPasteboard.general.string = "stopandshoot://mark"
                        model.notice = "Copied"
                    }
                }
                section("Location") {
                    Text(TravelCopy.locationUse)
                    Text("The system permission is While Using the App. This project does not ask for Always, and it does not keep GPS running in the background.")
                    Text("Grant location once while you are parked before you rely on Siri on the road. The first prompt needs a tap.")
                }
                section("Lookups") {
                    Toggle(isOn: $model.lookupsEnabled) {
                        Text("Look up place, weather, and nearby services")
                    }
                    Text(TravelCopy.lookupDisclosure)
                }
                section("Saved spots") {
                    Text("Spots are a JSON file in this app's local storage. They are not in an account, and they are not the website's browser list. Export JSON from the site and import it here. Import adds spots whose ids are new. It does not delete or overwrite spots already on this phone.")
                    Text("The backup menu on the main screen writes JSON, GPX, or CSV, or imports a JSON backup.")
                    if let notice = model.notice { Text(notice).foregroundStyle(Theme.muted) }
                }
                section("Notes") {
                    Text("Notes, tags, and parking observations are for when you are parked. Speak uses the microphone only after you tap it, and only with on-device speech recognition when the phone supports that. This app does not listen while you drive.")
                }
                section("This build") {
                    Text("\(AppIdentity.name) \(bundleVersion)")
                    Text("Bundle id: \(Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier)")
                    Text("The bundle id dev.provisional.stopandshoot is provisional. Change it before any signed, TestFlight, or App Store build. This project has not been submitted.")
                    Text("Map, fuel, and weather providers are named on each result. Parking rules are not inferred. Confirm the signs where you stop.")
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bundleVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? AppIdentity.marketingVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? AppIdentity.buildNumber
        return "\(short) (\(build))"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .font(.body)
        .card()
    }
}

private extension View {
    func card() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
