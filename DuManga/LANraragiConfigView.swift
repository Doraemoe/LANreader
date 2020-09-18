//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct LANraragiConfigView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @State var url = ""
    @State var apiKey = ""

    var body: some View {
        if store.state.setting.errorCode != nil {
            let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                    subtitle: NSLocalizedString("error.host", comment: "host error"),
                    style: .danger)
            banner.show()
            self.store.dispatch(.setting(action: .resetState))
        } else if store.state.setting.savedSuccess {
            self.store.dispatch(.setting(action: .resetState))
            self.presentationMode.wrappedValue.dismiss()
        }

        return VStack {
            TextField("lanraragi.config.url", text: self.$url)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            SecureField("lanraragi.config.apiKey", text: self.$apiKey)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            Button(action: {
                self.store.dispatch(.setting(action: .verifyAndSaveLanraragiConfig(url: self.url, apiKey: self.apiKey)))
            }, label: {
                Text("lanraragi.config.submit")
                        .font(.headline)
            })
                    .padding()
        }
        .onAppear(perform: {
            self.url = self.store.state.setting.url
            self.apiKey = self.store.state.setting.apiKey
        })
    }
}

struct LANraragiConfigView_Previews: PreviewProvider {
    static var previews: some View {
        LANraragiConfigView()
    }
}
