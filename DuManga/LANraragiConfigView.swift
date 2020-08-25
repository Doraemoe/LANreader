//  Created 23/8/20.

import SwiftUI

struct LANraragiConfigView: View {
    @State var url: String = ""
    @State var apiKey: String = ""
    @Binding var settingView: Bool
    
    var body: some View {
        VStack {
            TextField("Host address, with http(s):// protocol", text: self.$url)
                .padding()
            SecureField("API Key, can be set in settings. This is not your password.", text: self.$apiKey)
                .padding()
            Button(action: {
                let config = ["url": self.url, "apiKey": self.apiKey]
                UserDefaults.standard.set(config, forKey: "LANraragi")
                self.settingView.toggle()
            }) {
                Text("Submit")
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
