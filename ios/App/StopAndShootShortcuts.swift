import AppIntents

struct StopAndShootShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkSpotIntent(),
            phrases: [
                "Mark spot in \(.applicationName)",
                "Mark a spot with \(.applicationName)",
                "Save this spot in \(.applicationName)"
            ],
            shortTitle: "Mark Spot",
            systemImageName: "mappin.and.ellipse"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .orange
}
