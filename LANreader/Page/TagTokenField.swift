import SwiftUI

enum ArchiveTagStyle {
    static func tint(for namespaceKey: String) -> Color {
        switch namespaceKey {
        case ArchiveDetailsTagParser.artistTag:
            return .orange
        case ArchiveDetailsTagParser.sourceTag:
            return .teal
        case ArchiveDetailsTagParser.dateTag:
            return .indigo
        case ArchiveDetailsTagParser.otherTag:
            return .secondary
        default:
            return .blue
        }
    }

    static func iconName(for namespaceKey: String) -> String? {
        switch namespaceKey {
        case ArchiveDetailsTagParser.sourceTag:
            return "link"
        case ArchiveDetailsTagParser.dateTag:
            return "calendar"
        default:
            return nil
        }
    }
}

struct TagTokenField: View {
    @Binding var text: String

    @State private var tokens: [String] = []
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !tokens.isEmpty {
                WrappingHStack(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                        tokenChip(token, index: index)
                    }
                }

                Divider()
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tint)

                TextField("archive.details.tags.add", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .submitLabel(.done)
                    .focused($inputFocused)
                    .onSubmit {
                        commitInput()
                        inputFocused = true
                    }
                    .onChange(of: input) { _, newValue in
                        splitCompletedTokens(in: newValue)
                        syncText()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        inputFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            inputFocused = true
        }
        .onAppear {
            tokens = ArchiveDetailsTagParser.tokens(from: text)
            input = ""
        }
    }

    private func tokenChip(_ token: String, index: Int) -> some View {
        let namespaceKey = ArchiveDetailsTagParser.namespaceKey(for: token)
        let tint = ArchiveTagStyle.tint(for: namespaceKey)

        return HStack(spacing: 6) {
            if let iconName = ArchiveTagStyle.iconName(for: namespaceKey) {
                Image(systemName: iconName)
                    .font(.caption2.weight(.bold))
            }

            Text(token)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                tokens.remove(at: index)
                syncText()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("archive.details.tags.remove"))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: 280, alignment: .leading)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private func commitInput() {
        tokens.append(contentsOf: ArchiveDetailsTagParser.tokens(from: input))
        input = ""
        syncText()
    }

    private func splitCompletedTokens(in value: String) {
        guard let lastSeparator = value.lastIndex(where: ArchiveDetailsTagParser.isTagSeparator) else {
            return
        }
        tokens.append(contentsOf: ArchiveDetailsTagParser.tokens(from: String(value[..<lastSeparator])))
        input = String(value[value.index(after: lastSeparator)...])
    }

    private func syncText() {
        let pending = input.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ArchiveDetailsTagParser.tagsString(from: pending.isEmpty ? tokens : tokens + [pending])
    }
}
