import SwiftUI

@main
struct QingReadApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var cloud = CloudLibraryStore()

    init() {
        YYTheme.configureNativeAppearance()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset") {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingRead")
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "yuying.library.grid")
            UserDefaults.standard.removeObject(forKey: "yuying.library.sort")
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-launch-preview") { BrandLaunchView() }
                else { RootView() }
                #else
                RootView()
                #endif
            }.environmentObject(library).environmentObject(cloud)
                .tint(YYTheme.accent)
                .preferredColorScheme(library.settings.systemColorScheme)
        }
    }
}
