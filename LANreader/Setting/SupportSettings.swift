import ComposableArchitecture
import SwiftUI

struct SupportSettings: View {
    @Environment(NavigationHelper.self) private var navigation
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            let store = Store(initialState: SupportFeature.State()) {
                SupportFeature()
            }
            navigation.push(UISupportViewController(store: store))
        } label: {
            HStack {
                Text("settings.support.title")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()
        Button {
            openURL(AppStoreReviewURL.native) { accepted in
                if !accepted {
                    openURL(AppStoreReviewURL.web)
                }
            }
        } label: {
            HStack {
                Text("settings.support.rateApp")
                Spacer()
                Image(systemName: "star.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
        .padding()
        Button {
            let issueURL = URL(string: "https://github.com/Doraemoe/LANreader/issues/new")!
            openURL(issueURL)
        } label: {
            HStack {
                Text("settings.support.reportIssue")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()
        Button {
            let store = Store(initialState: LogFeature.State()) {
                LogFeature()
            }
            navigation.push(UILogViewController(store: store))
        } label: {
            HStack {
                Text("settings.debug.log")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()
        // swiftlint:disable force_cast
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
        let build = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
        // swiftlint:enable force_cast
        LabeledContent("version", value: "\(version)-\(build)")
            .padding()
    }
}

private enum AppStoreReviewURL {
    static let native = URL(string: "itms-apps://itunes.apple.com/app/id6743684988?action=write-review")!
    static let web = URL(string: "https://apps.apple.com/app/id6743684988?action=write-review")!
}
