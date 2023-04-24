// Created 3/9/20

import SwiftUI
import NotificationBannerSwift

struct ArchiveDetails: View {
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
                    NavigationLink(destination: SearchView(keyword: String(tag), showSearchResult: true)) {
                        Text(tag)
                    }
                        .padding()
                        .controlSize(.mini)
                        .foregroundColor(.white)
                        .background(.blue)
                        .clipShape(Capsule())
                })
                .padding()
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
}

struct ArchiveDetails_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveDetails(item: ArchiveItem(id: "id", name: "name", tags: "tags",
                isNew: true, progress: 0, pagecount: 10, dateAdded: 12345))
    }
}
