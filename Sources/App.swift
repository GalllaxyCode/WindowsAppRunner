import SwiftUI

@main
struct WindowsAppRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        Window("Windows App Runner", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 680, minHeight: 480)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 600)

        Settings {
            AppSettingsView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// .exe files dropped on the Dock icon or opened with the app: remember them and launch.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if let id = Store.shared.add(url) { Store.shared.launch(id) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
