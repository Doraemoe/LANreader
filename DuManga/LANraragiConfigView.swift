//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct LANraragiConfigView: View {
    @Environment(\.presentationMode) var presentationMode

    @FocusState private var focused: Bool

    @StateObject var configModel = LANraragiConfigViewModel()

    var body: some View {
        VStack {
            TextField("lanraragi.config.url", text: self.$configModel.url)
                .textContentType(.URL)
                .keyboardType(.URL)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
            SecureField("lanraragi.config.apiKey", text: self.$configModel.apiKey)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focused)
            Button(action: {
                Task {
                    let result = await configModel.verifyAndSave()
                    if result {
                        focused = false
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }, label: {
                Text("lanraragi.config.submit")
                    .font(.headline)
            })
            .disabled(configModel.isVerifying)
            .padding()
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: configModel.errorMessage, perform: { errorMessage in
            if !errorMessage.isEmpty {
                let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"),
                                                subtitle: errorMessage,
                                                style: .danger)
                banner.show()
                configModel.reset()
            }
        })
    }
}
