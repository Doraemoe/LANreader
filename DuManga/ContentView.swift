//
//  ContentView.swift
//  DuManga
//
//  Created by Jin Yifan on 22/8/20.
//  Copyright © 2020 Jin Yifan. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @State var settingView = UserDefaults.standard.dictionary(forKey: "LANraragi") == nil
    
    var body: some View {
            VStack(alignment: .leading) {
                if (self.settingView) {
                    LANraragiConfigView(settingView: $settingView)
                } else {
                    ArchiveList(settingView: $settingView)
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        UserDefaults.standard.removeObject(forKey: "LANraragi")
        return ContentView()
    }
}
