import AppIntents

/// Siri ve Kestirmeler: "Günlük Düzen su ekle"
@available(iOS 16.0, *)
struct GunlukShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddWaterIntent(),
                    phrases: ["\(.applicationName) su ekle",
                              "\(.applicationName) ile su içtim",
                              "\(.applicationName) bir bardak su"],
                    shortTitle: "Su ekle",
                    systemImageName: "drop.fill")
    }
}
