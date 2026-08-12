import SwiftUI

@main
struct VoltaAutoUpdateApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Volta 自动更新", id: "dashboard") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 960, height: 740)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Volta 自动更新", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
