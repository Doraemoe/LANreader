import SwiftUI

struct AdvancedSettings: View {
    let onTranslationTap: () -> Void

    var body: some View {
        Button(action: onTranslationTap) {
            HStack {
                Text("settings.advanced.translation")
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
