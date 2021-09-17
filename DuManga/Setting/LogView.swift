//
//  Created on 17/9/21.
//

import SwiftUI

struct LogView: View {
    
    @State var log = ""
    
    var body: some View {
        Text(log)
            .contextMenu {
                    Button(action: {
                        UIPasteboard.general.string = log
                    }) {
                        Text("copy")
                        }
                    }
            .onAppear(perform: {
                do {
                    let logFileURL = try FileManager.default
                        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                        .appendingPathComponent("app.log")
                    log = try String(contentsOf: logFileURL, encoding: .utf8)
                } catch {
                    log = "error reading log"
                }
            })
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView()
    }
}
