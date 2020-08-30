//  Created 23/8/20.

import SwiftUI

struct LANraragiConfigView: View {
    @State var url: String = (UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String])?["url"] ?? ""
    @State var apiKey: String = (UserDefaults.standard.dictionary(forKey: "LANraragi") as? [String: String])?["apiKey"] ?? ""
    @Binding var settingView: Bool
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            TextField("lanraragi.config.url", text: self.$url)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            SecureField("lanraragi.config.apiKey", text: self.$apiKey)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button(action: {
                let config = ["url": self.url, "apiKey": self.apiKey]
                UserDefaults.standard.set(config, forKey: "LANraragi")
                self.settingView.toggle()
                self.presentationMode.wrappedValue.dismiss()
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
