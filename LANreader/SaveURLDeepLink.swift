import Foundation

// Compiled into both the app and the Save URL extension, so the link the extension builds and the
// one `DeepLink` parses come from the same definition.
extension URL {
    /// The `lanreader://download` link that asks the app to queue this URL for download.
    var lanReaderAppDeepLink: URL {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        let encoded = absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        return URL(string: "lanreader://download?url=\(encoded)")!
    }
}
