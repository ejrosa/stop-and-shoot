import AppIntents
import Foundation
import StopAndShootLogic

struct MarkSpotIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Spot"
    static var description = IntentDescription("Saves your current location as a Stop & Shoot spot. Opens the app to read location while you are using it. Does not listen in the background.")
    /// While Using location cannot be read unless the app is open. This is not a background listener.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Note", description: "Optional words saved with the spot. Leave this empty and Siri should not ask for it.")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let speech = await AppModel.shared.markSpot(note: note, tags: [], announceInApp: false)
        return .result(dialog: IntentDialog(stringLiteral: speech))
    }
}
