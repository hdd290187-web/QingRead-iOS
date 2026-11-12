import SwiftUI

@main
struct QingReadApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(library.settings.systemColorScheme)
        }
    }
}
