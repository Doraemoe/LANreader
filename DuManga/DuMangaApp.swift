// Created 20/9/20

import SwiftUI

@main
struct DuMangaApp: App {
    let store = AppStore(initialState: .init(), reducer: appReducer, middlewares: [
        settingMiddleware(service: SettingsService()),
        lanraragiMiddleware(service: LANraragiService.shared)
    ])
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
