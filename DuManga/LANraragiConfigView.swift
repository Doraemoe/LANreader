//  Created 23/8/20.

import SwiftUI
import NotificationBannerSwift

struct LANraragiConfigView: View {
    static let banner = NotificationBanner(title: NSLocalizedString("error", comment: "error"), subtitle: NSLocalizedString("error.host", comment: "host error"), style: .danger)
    
    @State var url: String = (UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String])?["url"] ?? ""
    @State var apiKey: String = (UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String])?["apiKey"] ?? ""
    @Binding var settingView: Bool
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            TextField("lanraragi.config.url", text: self.$url)
                .textContentType(.URL)
                .keyboardType(.URL)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            SecureField("lanraragi.config.apiKey", text: self.$apiKey)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button(action: {
                let client = LANRaragiClient(url: self.url, apiKey: self.apiKey)
                client.healthCheck { healthy in
                    if healthy {
                        let config = ["url": self.url, "apiKey": self.apiKey]
                        UserDefaults.standard.set(config, forKey: "LANraragi")
                        self.settingView = false
                        self.presentationMode.wrappedValue.dismiss()
                    } else {
                        LANraragiConfigView.banner.show()
                    }
                }
                
            }) {
                Text("lanraragi.config.submit")
                    .font(.headline)
            }
            .padding()
        }
    }
}

struct LANraragiConfigView_Previews: PreviewProvider {
    static var previews: some View {
        LANraragiConfigView(settingView: Binding.constant(true))
    }
}
