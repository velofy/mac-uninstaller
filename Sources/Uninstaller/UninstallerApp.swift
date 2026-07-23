import SwiftUI

@main
struct UninstallerApp: App {
    var body: some Scene {
        WindowGroup("Uninstaller") {
            RootView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 940, height: 640)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
