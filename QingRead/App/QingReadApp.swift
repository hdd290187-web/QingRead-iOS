import SwiftUI

@main
struct QingReadApp: App {
    @StateObject private var library = LibraryStore()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset") {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingRead")
            try? FileManager.default.removeItem(at: root)
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(library.settings.systemColorScheme)
        }
    }
}
