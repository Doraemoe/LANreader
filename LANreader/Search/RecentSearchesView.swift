import ComposableArchitecture
import SwiftUI

struct RecentSearchesView: View {
    let store: StoreOf<SearchFeature>
    let onSelect: (String) -> Void

    var body: some View {
        List {
            Section {
                ForEach(store.recentSearches, id: \.self) { keyword in
                    row(keyword)
                }
            } header: {
                HStack {
                    Text("search.recent.title")
                    Spacer()
                    Button("search.recent.clear") {
                        store.send(.clearRecentSearches)
                    }
                    .font(.body)
                }
                .textCase(nil)
            }
            .headerProminence(.increased)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    private func row(_ keyword: String) -> some View {
        Button {
            onSelect(keyword)
        } label: {
            Label {
                Text(keyword)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }
}
