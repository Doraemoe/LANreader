// Created 3/12/20

import SwiftUI

struct DatabaseSettings: View {
    @State private var size = ""

    private let database = AppDatabase.shared
    private let store = AppStore.shared

    func setDatabaseSize() {
        do {
            let dbSize = try database.databaseSize()!
            let bcf = ByteCountFormatter()
            bcf.allowedUnits = [.useMB]
            size = bcf.string(fromByteCount: Int64(dbSize))
        } catch {
            size = NSLocalizedString("settings.database.error", comment: "read db error")
        }
    }

    var body: some View {
        return List {
            Button(role: .destructive, action: {
                do {
                    try database.clearDatabase()
                    store.dispatch(.archive(action: .clearArchive))
                    store.dispatch(.category(action: .clearCategory))
                    self.setDatabaseSize()
                } catch {
                    // NOOP
                }
            }, label: {
                HStack {
                    Text("settings.database.clear")
                    Spacer()
                    Text(size)
                            .foregroundColor(.secondary)
                }
                        .padding()
            })
        }
                .onAppear(perform: self.setDatabaseSize)
    }
}
