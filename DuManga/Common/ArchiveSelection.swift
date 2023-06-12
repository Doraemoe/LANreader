import SwiftUI
import NotificationBannerSwift

struct ArchiveSelection: View {
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue

    @State var selected: Set<String> = .init()
    @State private var showingAlert = false
    @StateObject var archiveSelectionModel = ArchiveSelectionModel()

    private let archives: [ArchiveItem]

    init(archives: [ArchiveItem]) {
        self.archives = archives
    }

    var body: some View {
        let archivesToDisplay = archiveSelectionModel.processArchives(archives: archives, sortOrder: archiveListOrder)
        let columns = [
            GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
        ]
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(archivesToDisplay) { item in
                    ArchiveGrid(archiveItem: item)
                        .onTapGesture {
                            if selected.contains(item.id) {
                                selected.remove(item.id)
                            } else {
                                selected.insert(item.id)
                            }
                        }
                        .overlay(alignment: .bottomTrailing, content: {
                            selected.contains(item.id) ? Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50)
                                .foregroundColor(.accentColor)
                                .padding()
                            : nil
                        })
                }
            }
            .padding()
        }
        .onAppear {
            archiveSelectionModel.connectStore()
        }
        .onDisappear {
            archiveSelectionModel.disconnectStore()
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    // Not yet implemented
                } label: {
                    Image(systemName: "folder.badge.plus")
                }

                Spacer()

                Text(
                    String.localizedStringWithFormat(
                        NSLocalizedString("archive.selected", comment: "count"),
                        selected.count
                    )
                )

                Spacer()

                Button(role: .destructive) {
                    showingAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(archiveSelectionModel.loading || selected.isEmpty)
                .alert("archive.selected.delete", isPresented: $showingAlert) {
                    Button("delete", role: .destructive) {
                        Task {
                            let removedIds = await archiveSelectionModel.deleteArchives(ids: selected)
                            removedIds.forEach { id in
                                selected.remove(id)
                            }
                        }
                    }
                    Button("cancel", role: .cancel) { }
                }
            }
        }
        .onChange(of: archiveSelectionModel.errorMessage) { errorMessage in
            if !errorMessage.isEmpty {
                let banner = NotificationBanner(
                    title: NSLocalizedString("error", comment: "error"),
                    subtitle: errorMessage,
                    style: .danger
                )
                banner.show()
                archiveSelectionModel.reset()
            }
        }
    }
}
