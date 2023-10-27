//
//  Created on 17/9/21.
//
import ComposableArchitecture
import SwiftUI

struct LogFeature: Reducer {
    struct State: Equatable {
        var log = ""
    }

    enum Action: Equatable {
        case setLog(String)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setLog(log):
                state.log = log
                return .none
            }
        }
    }
}

struct LogView: View {

    let store: StoreOf<LogFeature>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            ScrollView {
                Text(viewStore.log)
                    .textSelection(.enabled)
            }
            .onAppear(perform: {
                do {
                    let logFileURL = try FileManager.default
                        .url(
                            for: .applicationSupportDirectory,
                            in: .userDomainMask,
                            appropriateFor: nil,
                            create: true
                        )
                        .appendingPathComponent("app.log")
                    let log = try String(contentsOf: logFileURL, encoding: .utf8)
                    viewStore.send(.setLog(log))
                } catch {
                    viewStore.send(.setLog("error reading log"))
                }
            })
            .toolbar(.hidden, for: .tabBar)
        }
    }
}
