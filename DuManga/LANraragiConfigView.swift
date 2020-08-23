//
//  LANraragiConfigView.swift
//  DuManga
//
//  Created by Jin Yifan on 23/8/20.
//  Copyright © 2020 Jin Yifan. All rights reserved.
//

import SwiftUI

struct LANraragiConfigView: View {
    @State var url: String = ""
    @State var apiKey: String = ""
    @Binding var settingView: Bool
    
    var body: some View {
        VStack {
            TextField("Host address", text: self.$url)
                .padding()
            SecureField("API Key", text: self.$apiKey)
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
