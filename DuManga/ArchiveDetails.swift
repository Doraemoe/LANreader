// Created 3/9/20

import SwiftUI
import NotificationBannerSwift

struct ArchiveDetails: View {
    private static let sourceTag = "source"
    private static let dateTag = "date_added"

    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode
    @State private var showingAlert = false
    @State private var editMode: EditMode = .inactive

    @StateObject var archiveDetailsModel = ArchiveDetailsModel()

    let item: ArchiveItem

    init(item: ArchiveItem) {
        self.item = item
    }

    var body: some View {
        VStack {
            if editMode == .active {
                TextField("", text: $archiveDetailsModel.title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
            } else {
                Text(archiveDetailsModel.title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
            }
            ThumbnailImage(id: item.id)
                    .scaledToFit()
                    .padding()
                    .frame(width: 200, height: 250)
            if editMode == .active {
                TextEditor(text: $archiveDetailsModel.tags)
                        .border(Color.secondary, width: 2)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 200, alignment: .center)
                        .disableAutocorrection(true)
                        .padding()
            } else {
                WrappingHStack(models: archiveDetailsModel.tags.split(separator: ","), viewGenerator: { tag in
                    parseTag(tag: String(tag))
                            .padding()
                            .controlSize(.mini)
                            .foregroundColor(.white)
                            .background(.blue)
                            .clipShape(Capsule())
                })
            }
            Button(action: { showingAlert = true },
                    label: {
                        Text("archive.delete")
                    })
                    .disabled(archiveDetailsModel.loading)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.red)
                    .cornerRadius(20)
                    .alert(isPresented: $showingAlert) {
                        Alert(
                                title: Text("archive.delete.confirm"),
                                primaryButton: .destructive(Text("delete")) {
                                    Task {
                                        if await archiveDetailsModel.deleteArchive(id: item.id) {
                                            store.dispatch(.archive(action: .removeDeletedArchive(id: item.id)))
                                            presentationMode.wrappedValue.dismiss()
                                        }
                                    }
                                },
                                secondaryButton: .cancel()
                        )
                    }
            Spacer()
        }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        EditButton()
                                .disabled(archiveDetailsModel.loading)
                    }
                }
                .environment(\.editMode, $editMode)
                .onAppear(perform: {
                    archiveDetailsModel.load(title: item.name, tags: item.tags)
                })
                .onDisappear(perform: {
                    archiveDetailsModel.reset()
                })
                .onChange(of: editMode) { [editMode] newMode in
                    if editMode == .active && newMode == .inactive {
                        let updated = ArchiveItem(
                                id: item.id,
                                name: archiveDetailsModel.title,
                                tags: archiveDetailsModel.tags,
                                isNew: item.isNew,
                                progress: item.progress,
                                pagecount: item.pagecount,
                                dateAdded: item.dateAdded
                        )
                        Task {
                            if await archiveDetailsModel.updateArchive(archive: updated) {
                                store.dispatch(.archive(action: .updateArchive(archive: updated)))
                                archiveDetailsModel.title = updated.name
                                archiveDetailsModel.tags = updated.tags
                            }
                        }
                    }
                }
                .onChange(of: archiveDetailsModel.isError, perform: { isError in
                    if isError {
                        let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                subtitle: archiveDetailsModel.errorMessage,
                                style: .danger)
                        banner.show()
                        archiveDetailsModel.reset()
                    }
                })
    }

    private func parseTag(tag: String) -> some View {
        let tagPair = tag.split(separator: ":")

        let tagName = tagPair[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let tagValue = tagPair.count == 2 ? tagPair[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if tagName == ArchiveDetails.sourceTag {
            let urlString = tagValue.hasPrefix("http") ? tagValue : "https://\(tagValue)"
            return AnyView(Link(destination: URL(string: urlString)!) {
                Text(tag)
            })
        }
        let processedTag: String
        if tagName == ArchiveDetails.dateTag {
            let date = Date(timeIntervalSince1970: TimeInterval(tagValue) ?? 0)
            processedTag = "\(ArchiveDetails.dateTag): \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            processedTag = tag
        }
        return AnyView(NavigationLink(processedTag) {
            SearchView(keyword: String(tag.trimmingCharacters(in: .whitespacesAndNewlines)))
        })
    }
}
