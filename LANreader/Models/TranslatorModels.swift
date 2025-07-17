import Foundation

struct TranslatorConfig: Encodable, Equatable {
    let detector: Detector
    let render: Render
    let translator: Translator
    let inpainter: InpainterConfig
    let maskDilationOffset: Int
}

struct Translator: Encodable, Equatable {
    let translator: TranslatorModel
    let targetLang: TargetLang
}

struct Detector: Encodable, Equatable {
    let detector: TextDetector
    let detectionSize: DetectionResolution
    let boxThreshold: Double
    let unclipRatio: Double
}

struct InpainterConfig: Encodable, Equatable {
    let inpainter: Inpainter
    let inpaintingSize: InpainterSize
}

struct Render: Encodable, Equatable {
    let direction: TextDirection
}

enum TextDetector: String, CaseIterable, Encodable {
    case `default`
    case ctd
    case paddle
}

enum DetectionResolution: Int, CaseIterable, Encodable {
    case res1024 = 1024
    case res1536 = 1536
    case res2048 = 2048
    case res2560 = 2560
}

enum TextDirection: String, CaseIterable, Encodable {
    case auto
    case horizontal
    case vertical
}

// swiftlint:disable identifier_name
enum Inpainter: String, CaseIterable, Encodable {
    case `default`
    case lama_large
    case lama_mpe
    case sd
    case none
    case original
}

enum InpainterSize: Int, CaseIterable, Encodable {
    case size516 = 516
    case size1024 = 1024
    case size2048 = 2048
    case size2560 = 2560
}

enum TranslatorModel: String, CaseIterable, Encodable {
    case none
    case sakura
    case chatgpt
    case deepseek
    case deepl
    case custom_openai
    case youdao
    case baidu
    case papago
    case caiyun
    case original
    case groq
    case offline
    case nllb
    case nllb_big
    case sugoi
    case jparacrawl
    case jparacrawl_big
    case m2m100
    case m2m100_big
    case mbart50
    case qwen2
    case qwen2_big
}
// swiftlint:enable identifier_name

enum TargetLang: String, CaseIterable, Codable {
    case CHS = "简体中文"                // Simplified Chinese
    case CHT = "繁體中文"                // Traditional Chinese
    case ENG = "English"               // English
    case CSY = "Čeština"               // Czech
    case NLD = "Nederlands"            // Dutch
    case FRA = "Français"              // French
    case DEU = "Deutsch"               // German
    case HUN = "Magyar"                // Hungarian
    case ITA = "Italiano"              // Italian
    case JPN = "日本語"                  // Japanese
    case KOR = "한국어"                   // Korean
    case PLK = "Polski"                // Polish
    case PTB = "Português (Brasil)"    // Portuguese (Brazilian)
    case ROM = "Română"                // Romanian
    case RUS = "Русский"               // Russian
    case ESP = "Español"               // Spanish
    case TRK = "Türkçe"                // Turkish
    case UKR = "Українська"             // Ukrainian
    case VIN = "Tiếng Việt"            // Vietnamese
    case ARA = "العربية"                // Arabic
    case SRP = "Српски"                // Serbian
    case HRV = "Hrvatski"              // Croatian
    case THA = "ไทย"                     // Thai
    case IND = "Bahasa Indonesia"      // Indonesian
    case FIL = "Filipino (Tagalog)"    // Filipino (Tagalog)

    // Custom encoding implementation
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(describing: self))
    }
}
