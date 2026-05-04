@preconcurrency import Foundation
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
  enum Error: Swift.Error {
    case inputProviderNotFound
    case loadedItemHasWrongType
    case urlNotFound
  }

  func beginRequest(with context: NSExtensionContext) {
    // Do not call super in an Action extension with no user interface
    nonisolated(unsafe) let unsafeContext = context

    do {
      let itemProvider = try Self.inputProvider(from: unsafeContext)
      itemProvider.loadItem(
        forTypeIdentifier: UTType.propertyList.identifier,
        options: nil
      ) { item, _ in
        let output = (try? Self.url(from: item).lanReaderAppDeepLink)
          .map(Self.output(wrapping:)) ?? []

        unsafeContext.completeRequest(returningItems: output)
      }
    } catch {
      unsafeContext.completeRequest(returningItems: [])
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
  private static func inputProvider(from context: NSExtensionContext) throws -> NSItemProvider {
    for case let item as NSExtensionItem in context.inputItems {
      guard let attachments = item.attachments else {
        continue
      }

      for itemProvider in attachments {
        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) else {
          continue
        }

        return itemProvider
      }
    }

    throw Error.inputProviderNotFound
  }

  /// Will look for an input item that might provide the property list that Javascript sent us
  private static func url(from item: NSSecureCoding?) throws -> URL {
    guard let dictionary = item as? [String: Any] else {
      throw Error.loadedItemHasWrongType
    }

    let input = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] ?? [:]
    guard let absoluteStringUrl = input["url"] as? String, let url = URL(string: absoluteStringUrl) else {
      throw Error.urlNotFound
    }

    return url
  }

  /// Wrap the output to the expected object so we send back results to JS
  private static func output(wrapping deeplink: URL) -> [NSExtensionItem] {
    let results = ["deeplink": deeplink.absoluteString]
    let dictionary = [NSExtensionJavaScriptFinalizeArgumentKey: results]
    let provider = NSItemProvider(item: dictionary as NSDictionary, typeIdentifier: UTType.propertyList.identifier)
    let item = NSExtensionItem()
    item.attachments = [provider]
    return [item]
  }
}
