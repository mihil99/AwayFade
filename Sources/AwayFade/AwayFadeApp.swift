import SwiftUI

@main
struct AwayFadeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            Label("AwayFade", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if model.isEnabled { return "wave.3.right.circle.fill" }
        return "wave.3.right.circle"
    }
}
