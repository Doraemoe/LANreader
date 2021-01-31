// Created 20/9/20

import SwiftUI

@main
struct DuMangaApp: App {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false

    let store = AppStore(initialState: .init(), reducer: appReducer, middlewares: [
        settingMiddleware(service: SettingsService()),
        lanraragiMiddleware(service: LANraragiService.shared)
    ])

    var body: some Scene {
        WindowGroup {
            ContentView()
                .blur(radius: blurInterfaceWhenInactive && scenePhase != .active ? 200 : 0)
                .environmentObject(store)
        }
    }
}
