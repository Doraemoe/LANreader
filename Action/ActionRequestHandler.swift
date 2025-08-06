import Foundation
import UniformTypeIdentifiers

// Sample code was sending this from a thread to another, let asume @Sendable for this
extension NSExtensionContext: @unchecked @retroactive Sendable {}

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling, Sendable {
  enum Error: Swift.Error {
    case inputProviderNotFound
    case loadedItemHasWrongType
    case urlNotFound
  }

  func beginRequest(with context: NSExtensionContext) {
    // Do not call super in an Action extension with no user interface
    Task {
      do {
        let url = try await url(from: context)
        await MainActor.run {
          let deeplink = url.lanReaderAppDeepLink
          let output = output(wrapping: deeplink)
          context.completeRequest(returningItems: output)
        }
      } catch {
        await MainActor.run {
          context.completeRequest(returningItems: [])
        }
      }
    }
  }
}

extension URL {

  var lanReaderAppDeepLink: URL {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
    components.scheme = "lanreader"
    return components.url!
  }
}

extension ActionRequestHandler {
  /// Will look for an input item that might provide the property list that Javascript sent us
  private func url(from context: NSExtensionContext) async throws -> URL {
      // swiftlint:disable force_cast
    for item in context.inputItems as! [NSExtensionItem] {
        // swiftlint:enable force_cast
      guard let attachments = item.attachments else {
        continue
      }
      for itemProvider in attachments {
        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) else {
          continue
        }
        guard let dictionary = try await itemProvider.loadItem(
            forTypeIdentifier: UTType.propertyList.identifier
        ) as? [String: Any] else {
          throw Error.loadedItemHasWrongType
        }
          // swiftlint:disable force_cast
        let input = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as! [String: Any]? ?? [:]
          // swiftlint:enable force_cast
        guard let absoluteStringUrl = input["url"] as? String, let url = URL(string: absoluteStringUrl) else {
          throw Error.urlNotFound
        }
        return url
      }
    }
    throw Error.inputProviderNotFound
  }

  /// Wrap the output to the expected object so we send back results to JS
  private func output(wrapping deeplink: URL) -> [NSExtensionItem] {
    let results = ["deeplink": deeplink.absoluteString]
    let dictionary = [NSExtensionJavaScriptFinalizeArgumentKey: results]
    let provider = NSItemProvider(item: dictionary as NSDictionary, typeIdentifier: UTType.propertyList.identifier)
    let item = NSExtensionItem()
    item.attachments = [provider]
    return [item]
  }
}
