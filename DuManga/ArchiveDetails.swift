// Created 3/9/20

import SwiftUI
import NotificationBannerSwift

struct ArchiveDetails: View {
    private static let sourceTag = "source"
    private static let dateTag = "date_added"

    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode
    @State private var showingAlert = false
    @State private var isEditing = false

    @StateObject var archiveDetailsModel = ArchiveDetailsModel()

    let item: ArchiveItem

    init(item: ArchiveItem) {
        self.item = item
    }

    var body: some View {
        VStack {
            if isEditing {
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
            if isEditing {
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
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.red)
                    .cornerRadius(20)
                    .alert(isPresented: $showingAlert) {
                        Alert(
                                title: Text("archive.delete.confirm"),
                                primaryButton: .destructive(Text("delete")) {
                                    store.dispatch(.archive(action: .deleteArchive(id: item.id)))
                                },
                                secondaryButton: .cancel()
                        )
                    }
            Spacer()
        }
                .navigationBarItems(trailing: Button(action: {
                    if isEditing {
                        let updated = ArchiveItem(id: item.id,
                                name: archiveDetailsModel.title,
                                tags: archiveDetailsModel.tags,
                                isNew: false,
                                progress: item.progress,
                                pagecount: item.pagecount,
                                dateAdded: item.dateAdded)
                        store.dispatch(.archive(action: .updateArchiveMetadata(metadata: updated)))
                        isEditing = false
                    } else {
                        isEditing = true
                    }

                }, label: {
                    if isEditing {
                        Text("save")
                    } else {
                        Text("edit")
                    }

                })
                        .disabled(archiveDetailsModel.loading)
                )
                .onAppear(perform: {
                    archiveDetailsModel.load(state: store.state,
                            title: item.name,
                            tags: item.tags)
                })
                .onDisappear(perform: {
                    archiveDetailsModel.unload()
                })
                .onChange(of: archiveDetailsModel.errorCode, perform: { errorCode in
                    if errorCode != nil {
                        let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                subtitle: NSLocalizedString("error.metadata.update", comment: "update metadata error"),
                                style: .danger)
                        banner.show()
                        store.dispatch(.archive(action: .resetState))
                    }
                })
                .onChange(of: archiveDetailsModel.updateSuccess, perform: { success in
                    if success {
                        store.dispatch(.archive(action: .resetState))
                        presentationMode.wrappedValue.dismiss()
                    }
                })
                .onChange(of: archiveDetailsModel.deleteSuccess, perform: { success in
                    if success {
                        store.dispatch(.archive(action: .resetState))
                        presentationMode.wrappedValue.dismiss()
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
        return AnyView(NavigationLink(
                destination: SearchView(
                        keyword: String(tag.trimmingCharacters(in: .whitespacesAndNewlines)),
                        showSearchResult: true)
        ) {
            Text(processedTag)
        })
    }
}

struct ArchiveDetails_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveDetails(item: ArchiveItem(id: "id", name: "name", tags: "tags",
                isNew: true, progress: 0, pagecount: 10, dateAdded: 12345))
    }
}
