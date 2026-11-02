import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("PaperStory", id: "main") {
            AppRootView()
                .frame(minWidth: 640, minHeight: 700)
        }
        .defaultSize(width: 900, height: 820)
        .windowResizability(.contentMinSize)
        #else
        WindowGroup {
            AppRootView()
        }
        #endif
    }
}
