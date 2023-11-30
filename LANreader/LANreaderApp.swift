// Created 20/9/20
import ComposableArchitecture
import SwiftUI
import Logging
import Puppy

@main
struct LANreaderApp: App {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false

    let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        do {
            if let tmp = try? FileManager.default.contentsOfDirectory(
                at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: []
            ) {
                tmp.forEach { url in
                    try? FileManager.default.removeItem(at: url)
                }
            }

            let logFileURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("app.log", conformingTo: .log)

            do {
                try FileManager.default.removeItem(at: logFileURL)
            } catch {
                // NOOP
            }

            if let sessionDownloadFolder = try? FileManager.default.contentsOfDirectory(
                at: FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                ).appendingPathComponent(LANraragiService.currentSessionDownloadFolder, conformingTo: .folder),
                includingPropertiesForKeys: []
            ) {
                sessionDownloadFolder.forEach { url in
                    try? FileManager.default.removeItem(at: url)
                }
            }

            let console = ConsoleLogger("com.jif.LANreader.console")
            let fileLogger = try FileLogger(
                "com.jif.LANreader.file",
                logLevel: .info,
                logFormat: LogFormatter(),
                fileURL: logFileURL
            )

            var puppy = Puppy()
            puppy.add(console)
            puppy.add(fileLogger)

            LoggingSystem.bootstrap {
                var handler = PuppyLogHandler(label: $0, puppy: puppy)
                handler.logLevel = .info
                return handler
            }
        } catch {
            fatalError("Unresolved error \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: self.store)
                .blur(radius: blurInterfaceWhenInactive && scenePhase != .active ? 200 : 0)
        }
    }
}
