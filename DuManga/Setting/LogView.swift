//
//  Created on 17/9/21.
//

import SwiftUI

struct LogView: View {

    @State var log = ""

    var body: some View {
        ScrollView {
            Text(log)
                .textSelection(.enabled)
        }
        .onAppear(perform: {
            do {
                let logFileURL = try FileManager.default
                    .url(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                    .appendingPathComponent("app.log")
                log = try String(contentsOf: logFileURL, encoding: .utf8)
            } catch {
                log = "error reading log"
            }
        })
        .toolbar(.hidden, for: .tabBar)
    }
}
