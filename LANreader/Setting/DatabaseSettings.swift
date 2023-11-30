// Created 3/12/20
import ComposableArchitecture
import SwiftUI
import Logging

@Reducer struct DatabaseSettingsFeature {
    private let logger = Logger(label: "DatabaseSettingsFeature")

    struct State: Equatable {
        var size = ""
    }

    enum Action: Equatable {
        case setDatabaseSize
        case clearDatabase
    }

    @Dependency(\.appDatabase) var database

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .setDatabaseSize:
            do {
                let dbSize = try database.databaseSize()!
                let bcf = ByteCountFormatter()
                bcf.allowedUnits = [.useMB]
                state.size = bcf.string(fromByteCount: Int64(dbSize))
            } catch {
                state.size = NSLocalizedString("settings.database.error", comment: "read db error")
            }
            return .none
        case .clearDatabase:
            do {
                try database.clearDatabase()
            } catch {
                logger.error("failed to clear database. \(error)")
            }
            return .run { send in
                await send(.setDatabaseSize)
            }
        }
    }

}

struct DatabaseSettings: View {

    let store: StoreOf<DatabaseSettingsFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            return List {
                Button(role: .destructive, action: {
                    viewStore.send(.clearDatabase)
                }, label: {
                    HStack {
                        Text("settings.database.clear")
                        Spacer()
                        Text(viewStore.size)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                })
            }
            .onAppear {
                viewStore.send(.setDatabaseSize)
            }
        }
    }
}
