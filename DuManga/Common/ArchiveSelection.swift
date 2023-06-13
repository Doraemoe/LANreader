import SwiftUI
import NotificationBannerSwift

struct ArchiveSelection: View {
    @AppStorage(SettingsKey.archiveListOrder) var archiveListOrder: String = ArchiveListOrder.name.rawValue

    @State var selected: Set<String> = .init()
    @State private var deleteAlert = false
    @State private var removeAlert = false
    @StateObject var archiveSelectionModel = ArchiveSelectionModel()

    private let archives: [ArchiveItem]
    private let archiveSelectFor: ArchiveSelectFor
    private let categoryId: String?

    init(archives: [ArchiveItem], archiveSelectFor: ArchiveSelectFor, categoryId: String? = nil) {
        self.archives = archives
        self.archiveSelectFor = archiveSelectFor
        self.categoryId = categoryId
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
                            if selected.contains(item.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50)
                                    .foregroundColor(.accentColor)
                                    .padding()
                            } else { Image(systemName: "circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50)
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        })
                }
            }
            .padding()
        }
        .task {
            await archiveSelectionModel.fetchCategories()
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
                if archiveSelectFor == .library || archiveSelectFor == .search {
                    Menu {
                        ForEach(archiveSelectionModel.getStaticCategories()) { category in
                            Button {
                                Task {
                                    let addedIds = await archiveSelectionModel.addArchivesToCategory(
                                        categoryId: category.id,
                                        archiveIds: selected
                                    )
                                    addedIds.forEach { id in
                                        selected.remove(id)
                                    }
                                }
                            } label: {
                                Text(category.name)
                            }
                        }
                        Text("archive.selected.category.add")
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .disabled(archiveSelectionModel.loading || selected.isEmpty)
                } else if archiveSelectFor == .categoryStatic {
                    Button(role: .destructive) {
                        removeAlert = true
                    } label: {
                        Image(systemName: "folder.badge.minus")
                    }
                    .disabled(archiveSelectionModel.loading || selected.isEmpty)
                    .alert("archive.selected.category.remove", isPresented: $removeAlert) {
                        Button(role: .destructive) {
                            Task {
                                let removedIds = await archiveSelectionModel.removeArchivesFromCategory(
                                    categoryId: categoryId!, archiveIds: selected
                                )
                                removedIds.forEach { id in
                                    selected.remove(id)
                                }
                            }
                        } label: {
                            Text("remove")
                        }

                        Button("cancel", role: .cancel) { }
                    }
                } else {
                    // placeholder
                    Color.clear
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
                    deleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(archiveSelectionModel.loading || selected.isEmpty)
                .alert("archive.selected.delete", isPresented: $deleteAlert) {
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
        .onChange(of: archiveSelectionModel.successMessage) { successMessage in
            if !successMessage.isEmpty {
                let banner = NotificationBanner(
                    title: NSLocalizedString("success", comment: "success"),
                    subtitle: successMessage,
                    style: .success
                )
                banner.show()
                archiveSelectionModel.reset()
            }
        }
    }
}
