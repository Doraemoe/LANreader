// Created 20/9/20
import ComposableArchitecture
import SwiftUI
import Logging
import Puppy
import GRDBQuery
import Dependencies

@main
struct LANreaderApp: App {
    @Environment(\.scenePhase) var scenePhase
    @Dependency(\.lanraragiService) var lanraragiService

    let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    private let transactionObserver = TransactionObserver()

    init() {
        do {
            let staleItems = PageStorage.takeStaleItems(
                temporaryFolder: FileManager.default.temporaryDirectory,
                sessionFolder: LANraragiService.downloadPath,
                legacySessionFolder: PageStorage.legacySessionFolder
            )
            Task.detached(priority: .utility) {
                PageStorage.remove(staleItems)
            }
            if let cachePath = LANraragiService.cachePath {
                try? PageStorage.excludeFromBackup(cachePath)
            }

            let logFileURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("app.log", conformingTo: .log)
            try? FileManager.default.removeItem(at: logFileURL)

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

            LoggingSystem.bootstrap { [puppy] in
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
                .blur(radius: store.blurInterfaceWhenInactive && scenePhase != .active ? 200 : 0)
                .task { await transactionObserver.start() }
                .task { await lanraragiService.checkServerVersionAtStartup() }
        }
        .databaseContext(.readOnly { AppDatabase.shared.dbReader })
    }
}
