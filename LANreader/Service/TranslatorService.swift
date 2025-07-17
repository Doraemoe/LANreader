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

    func translatePage(original: URL) -> DataStreamRequest? {
        let urlString = UserDefaults.standard.string(forKey: SettingsKey.translationUrl) ?? ""

        guard let data = UIImage(
            contentsOfFile: original.path(percentEncoded: false)
        )?.jpegData(compressionQuality: 0.8),
              let url = URL(string: "\(urlString)/translate/with-form/image/stream") else {
            Self.logger.error("Failed to get image data or create URL.")
            return nil
        }

        let config = buildConfig()

        let multipartFormData = MultipartFormData()
        multipartFormData.append(data, withName: "image", fileName: "image.jpeg", mimeType: "image/jpeg")
        if let configData = try? self.snakeCaseEncoder.encode(config) {
            multipartFormData.append(configData, withName: "config", mimeType: "application/json")
        }

        do {
            var request = try URLRequest(url: url, method: .post)
            request.httpBody = try multipartFormData.encode()
            request.setValue(multipartFormData.contentType, forHTTPHeaderField: "Content-Type")

            return session.streamRequest(request).validate()
        } catch {
            Self.logger.error("Failed to create multipart request: \(error)")
            return nil
        }
    }

    private func buildConfig() -> TranslatorConfig {
        let translator = UserDefaults.standard.string(forKey: SettingsKey.translationService) ?? "none"
        let targetLang = UserDefaults.standard.string(forKey: SettingsKey.translationTarget) ?? "CHS"
        let unclipRatio = UserDefaults.standard.object(forKey: SettingsKey.translationUnclipRatio) as? Double ?? 0
        let boxThreshold = UserDefaults.standard.object(forKey: SettingsKey.translationBoxThreshold) as? Double ?? 0.7
        let maskDilationOffset = UserDefaults.standard.object(
            forKey: SettingsKey.translationMaskDilationOffset
        ) as? Int ?? 30
        let detectionResolution = UserDefaults.standard.object(
            forKey: SettingsKey.translationDetectionResolution
        ) as? Int ?? 1536
        let textDetector = UserDefaults.standard.string(forKey: SettingsKey.translationTextDetector) ?? "default"
        let renderTextDirection = UserDefaults.standard.string(
            forKey: SettingsKey.translationRenderTextDirection
        ) ?? "auto"
        let inpaintingSize = UserDefaults.standard.object(forKey: SettingsKey.translationInpaintingSize) as? Int ?? 2048
        let inpainter = UserDefaults.standard.string(forKey: SettingsKey.translationInpainter) ?? "lama_large"

        return TranslatorConfig(
            detector: Detector(
                detector: TextDetector(rawValue: textDetector) ?? .default,
                detectionSize: DetectionResolution(rawValue: detectionResolution) ?? .res1536,
                boxThreshold: boxThreshold,
                unclipRatio: unclipRatio
            ),
            render: Render(direction: TextDirection(rawValue: renderTextDirection) ?? .auto),
            translator: Translator(
                translator: TranslatorModel(rawValue: translator) ?? .none,
                targetLang: TargetLang(rawValue: targetLang) ?? .CHS
            ),
            inpainter: InpainterConfig(
                inpainter: Inpainter(rawValue: inpainter) ?? .lama_large,
                inpaintingSize: InpainterSize(rawValue: inpaintingSize) ?? .size2048
            ),
            maskDilationOffset: maskDilationOffset
        )
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
