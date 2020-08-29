//  Created 23/8/20.

import SwiftUI

struct LANraragiConfigView: View {
    @State var url: String = ""
    @State var apiKey: String = ""
    @Binding var settingView: Bool
    
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
