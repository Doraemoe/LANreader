// Created 20/9/20

import SwiftUI
import Logging
import FileLogging

@main
struct DuMangaApp: App {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false

    init() {
        do {
            let logFileURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("app.log")

            do {
                try FileManager.default.removeItem(at: logFileURL)
            } catch {
                // NOOP
            }

            let fileLogger = try FileLogging(to: logFileURL)

            LoggingSystem.bootstrap { label in
                let handlers: [LogHandler] = [
                    FileLogHandler(label: label, fileLogger: fileLogger),
                    StreamLogHandler.standardOutput(label: label)
                ]

                return MultiplexLogHandler(handlers)
            }
        } catch {
            fatalError("Unresolved error \(error)")
        }
    }

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
