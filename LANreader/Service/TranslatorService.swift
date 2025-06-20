import Foundation
import UIKit
import Alamofire
import Logging
import Dependencies

class TranslatorService: NSObject {
    private static let logger = Logger(label: "TranslatorService")

    private static var _shared: TranslatorService?

    private var session: Session
    private let snakeCaseEncoder: JSONEncoder

    private override init() {
        self.session = Session()
        self.snakeCaseEncoder = JSONEncoder()
        self.snakeCaseEncoder.keyEncodingStrategy = .convertToSnakeCase
    }

    public static var shared: TranslatorService {
        if _shared == nil {
            _shared = TranslatorService()
        }
        return _shared!
    }

    func translatePage(original: URL) -> UploadRequest {
        let url = UserDefaults.standard.string(forKey: SettingsKey.translationUrl) ?? ""
        let translator = UserDefaults.standard.string(forKey: SettingsKey.translationService) ?? "none"
        let targetLang = UserDefaults.standard.string(forKey: SettingsKey.translationTarget) ?? "CHS"

        let data = UIImage(contentsOfFile: original.path(percentEncoded: false))?.jpegData(compressionQuality: 0.8)
        let config = TranslatorConfig(
            translator: Translator(
                translator: TranslatorModel(rawValue: translator)!,
                targetLang: TargetLang(rawValue: targetLang)!
            )
        )

        return session.upload(multipartFormData: { multipart in
            multipart.append(data!, withName: "image", fileName: "image.jpeg", mimeType: "image/jpeg")
            if let configData = try? self.snakeCaseEncoder.encode(config) {
                multipart.append(configData, withName: "config", mimeType: "application/json")
            }
        }, to: "\(url)/translate/with-form/image", method: .post)
        .validate()
    }

    static func resetService() {
        _shared = nil
    }
}

extension TranslatorService: DependencyKey {
    static let liveValue = TranslatorService.shared
    static let testValue = TranslatorService.shared
}

extension DependencyValues {
  var translatorService: TranslatorService {
    get { self[TranslatorService.self] }
    set { self[TranslatorService.self] = newValue }
  }
}
