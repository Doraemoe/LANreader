// Created 3/9/20

import SwiftUI
import NotificationBannerSwift

struct ArchiveDetails: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @StateObject var archiveListModel = ArchiveDetailsModel()

    let item: ArchiveItem

    init(item: ArchiveItem) {
        self.item = item
    }

    var body: some View {
        VStack {
            TextField("", text: $archiveListModel.title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
            ThumbnailImage(id: item.id)
                    .scaledToFit()
                    .padding()
                    .frame(width: 200, height: 250)
            TextEditor(text: $archiveListModel.tags)
                    .border(Color.secondary, width: 2)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 200, alignment: .center)
                    .disableAutocorrection(true)
                    .padding()
            Spacer()
        }
                .navigationBarItems(trailing: Button(action: {
                    let updated = ArchiveItem(id: self.item.id,
                            name: archiveListModel.title,
                            tags: archiveListModel.tags,
                            isNew: false,
                            progress: 0)
                    self.store.dispatch(.archive(action: .updateArchiveMetadata(metadata: updated)))
                }, label: {
                    Text("save")
                })
                        .disabled(archiveListModel.loading)
                )
                .onAppear(perform: {
                    archiveListModel.load(state: store.state,
                            title: self.item.name,
                            tags: self.item.tags)
                })
                .onDisappear(perform: {
                    archiveListModel.unload()
                })
                .onChange(of: archiveListModel.errorCode, perform: { errorCode in
                    if errorCode != nil {
                        let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                subtitle: NSLocalizedString("error.metadata.update", comment: "update metadata error"),
                                style: .danger)
                        banner.show()
                        self.store.dispatch(.archive(action: .resetState))
                    }
                })
                .onChange(of: archiveListModel.updateSuccess, perform: { success in
                    if success {
                        self.store.dispatch(.archive(action: .resetState))
                        self.presentationMode.wrappedValue.dismiss()
                    }
                })
    }
}

struct ArchiveDetails_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveDetails(item: ArchiveItem(id: "id", name: "name", tags: "tags", isNew: true, progress: 0))
    }
}
