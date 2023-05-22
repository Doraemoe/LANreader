// Created 20/9/20

import SwiftUI
import Logging
import Puppy

@main
struct DuMangaApp: App {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKey.blurInterfaceWhenInactive) var blurInterfaceWhenInactive: Bool = false
    @AppStorage(SettingsKey.passcode) var storedPasscode: String = ""
    @AppStorage(SettingsKey.lanraragiUrl) var lanraragiUrl: String = ""

    @State var lock = false

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
                    .appendingPathComponent("app.log")

            do {
                try FileManager.default.removeItem(at: logFileURL)
            } catch {
                // NOOP
            }

            let console = ConsoleLogger("com.jif.DuManga.console")
            let fileLogger = try FileLogger("com.jif.DuManga.file", logLevel: .info, fileURL: logFileURL)

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

    let store = AppStore(initialState: .init(), reducer: appReducer, middlewares: [])

    var body: some Scene {
        WindowGroup {
            if lanraragiUrl.isEmpty {
                LANraragiConfigView()
            } else {
                ZStack {
                    ContentView()
                    // As of iOS 16, use .blur will case nav title overlap with safe area
                    if blurInterfaceWhenInactive && scenePhase != .active {
                        Color.primary.colorInvert()
                    }
                }
                        .environmentObject(store)
                        .fullScreenCover(isPresented: $lock.animation(nil)) {
                            LockScreen(initialState: LockScreenState.normal,
                                    storedPasscode: storedPasscode) { passcode, _, act in
                                if passcode == storedPasscode {
                                    lock = false
                                    act(true)
                                } else {
                                    act(false)
                                }
                            }
                        }
                        .onChange(of: scenePhase) { newPhase in
                            if !storedPasscode.isEmpty && newPhase == .inactive {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    lock = true
                                }
                            }
                        }
            }
        }
    }
}
