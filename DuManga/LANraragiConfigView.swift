//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct LANraragiConfigView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.presentationMode) var presentationMode

    @StateObject var configModel = LANraragiConfigViewModel()
    @Binding var notLoggedIn: Bool

    var body: some View {
        VStack {
            TextField("lanraragi.config.url", text: self.$configModel.url)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disableAutocorrection(true)
            SecureField("lanraragi.config.apiKey", text: self.$configModel.apiKey)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            Button(action: {
                Task {
                    await store.dispatch(verifyAndSaveLanraragiConfig(
                            url: configModel.url, apiKey: configModel.apiKey))
                }
            }, label: {
                Text("lanraragi.config.submit")
                        .font(.headline)
            })
                    .padding()
        }
        .onAppear(perform: {
            configModel.load(state: store.state)
        })
        .onDisappear(perform: {
            configModel.unload()
        })
        .onChange(of: configModel.errorCode, perform: { errorCode in
            if errorCode != nil {
                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                        subtitle: NSLocalizedString("error.host", comment: "host error"),
                        style: .danger)
                banner.show()
                store.dispatch(.setting(action: .resetState))
            }
        })
        .onChange(of: configModel.savedSuccess, perform: { success in
            if success {
                store.dispatch(.setting(action: .resetState))
                presentationMode.wrappedValue.dismiss()
                if notLoggedIn {
                    self.notLoggedIn = false
                }
            }
        })
    }
}

struct LANraragiConfigView_Previews: PreviewProvider {
    static var previews: some View {
        LANraragiConfigView(notLoggedIn: Binding.constant(true))
    }
}
