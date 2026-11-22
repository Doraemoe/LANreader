import SwiftUI

struct ServerSettings: View {
    let onConfigTap: () -> Void
    let onUploadTap: () -> Void

    var body: some View {
        Button(action: onConfigTap) {
            HStack {
                Text("settings.host.config")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()

        Button(action: onUploadTap) {
            HStack {
                Text("settings.host.upload")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()
    }
}
