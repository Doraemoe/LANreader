//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct LANraragiConfigView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @StateObject var configModel = LANraragiConfigViewModel()

    var body: some View {
        VStack {
            TextField("lanraragi.config.url", text: self.$configModel.url)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            SecureField("lanraragi.config.apiKey", text: self.$configModel.apiKey)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            Button(action: {
                self.store.dispatch(.setting(action: .verifyAndSaveLanraragiConfig(
                        url: self.configModel.url, apiKey: self.configModel.apiKey)))
            }, label: {
                Text("lanraragi.config.submit")
                        .font(.headline)
            })
                    .padding()
        }
        .onAppear(perform: {
            self.configModel.load(state: store.state)
        })
        .onDisappear(perform: {
            self.configModel.unload()
        })
        .onChange(of: self.configModel.errorCode, perform: { errorCode in
            if errorCode != nil {
                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                        subtitle: NSLocalizedString("error.host", comment: "host error"),
                        style: .danger)
                banner.show()
                self.store.dispatch(.setting(action: .resetState))
            }
        })
        .onChange(of: self.configModel.savedSuccess, perform: { success in
            if success {
                self.store.dispatch(.setting(action: .resetState))
                self.presentationMode.wrappedValue.dismiss()
            }
        })
    }
}

struct LANraragiConfigView_Previews: PreviewProvider {
    static var previews: some View {
        LANraragiConfigView()
    }
}
