//Created 3/9/20

import SwiftUI
import NotificationBannerSwift

struct ArchiveDetails: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @State var title = ""
    @State var tags = ""
    let item: ArchiveItem

    init(item: ArchiveItem) {
        self.item = item
    }

    var body: some View {
        if store.state.archive.errorCode != nil {
            let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                    subtitle: NSLocalizedString("error.metadata.update", comment: "update metadata error"),
                    style: .danger)
            banner.show()
            self.store.dispatch(.archive(action: .resetState))
        } else if store.state.archive.updateArchiveMetadataSuccess {
            self.store.dispatch(.archive(action: .resetState))
            self.presentationMode.wrappedValue.dismiss()
        }
        return VStack {
            TextField("", text: self.$title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            item.thumbnail
                .resizable()
                .scaledToFit()
                .padding()
                .frame(width: 200, height: 250)
            TextEditor(text: self.$tags)
                .border(Color.secondary, width: 2)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 200, alignment: .center)
                .disableAutocorrection(true)
                .padding()
            Spacer()
        }
        .navigationBarItems(trailing: Button(action: {
            let updated = ArchiveItem(id: self.item.id,
                    name: self.title,
                    tags: self.tags,
                    thumbnail: self.item.thumbnail)
            self.store.dispatch(.archive(action: .updateArchiveMetadata(metadata: updated)))
        }, label: {
            Text("save")
        })
                .disabled(self.store.state.archive.loading)
        )
        .onAppear(perform: {
            self.title = self.item.name
            self.tags = self.item.tags
        })
    }
}

struct ArchiveDetails_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveDetails(item: ArchiveItem(id: "id", name: "name", tags: "tags", thumbnail: Image("placeholder")))
    }
}
