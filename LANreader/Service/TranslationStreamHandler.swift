import Alamofire
import Foundation

enum TranslationStatus: Equatable {
    case completed(Data)
    case progress(String)
    case error(String)
    case pending(queuePosition: String?)
}

class TranslationStreamHandler {
    private var buffer = Data()

    func processStreamResponse(_ request: DataStreamRequest) -> AsyncThrowingStream<TranslationStatus, Error> {
        return AsyncThrowingStream { continuation in
            request.responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    switch result {
                    case .success(let data):
                        let status = self.processChunk(data)
                        continuation.yield(status)

                        // If we have a final result, we're done
                        if case .completed = status {
                            continuation.finish()
                        }

                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }

                case .complete(let response):
                    if let error = response.error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }

    func handleProgressCode(code: String) -> String {
        switch code {
        case "upload":
            return String(localized: "translation.progress.uploading")
        case "detection":
            return String(localized: "translation.progress.detection")
        case "ocr":
            return String(localized: "translation.progress.ocr")
        case "mask-generation":
            return String(localized: "translation.progress.mask-generation")
        case "inpainting":
            return String(localized: "translation.progress.inpainting")
        case "upscaling":
            return String(localized: "translation.progress.upscaling")
        case "translating":
            return String(localized: "translation.progress.translating")
        case "rendering":
            return String(localized: "translation.progress.rendering")
        case "finished":
            return String(localized: "translation.progress.finished")
        case "Processing":
            return String(localized: "translation.progress.processing")
        case "textline_merge":
            return String(localized: "translation.progress.textline_merge")
        case "error-translating":
            return String(localized: "translation.progress.error-translating")
        default:
            return code
        }
    }

    private func processChunk(_ value: Data) -> TranslationStatus {
        buffer.append(value)

        var latestStatus: TranslationStatus = .progress("Processing")

        while buffer.count >= 5 {
            guard buffer.count >= 5 else { break }

            // Fix: Read bytes individually to avoid alignment issues
            // swiftlint:disable identifier_name
            let dataSize: UInt32 = buffer.withUnsafeBytes { bytes in
                let b1 = UInt32(bytes[1])
                let b2 = UInt32(bytes[2])
                let b3 = UInt32(bytes[3])
                let b4 = UInt32(bytes[4])
                // Construct a big-endian UInt32 manually (most significant byte first)
                return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
            }
            // swiftlint:enable identifier_name

            let totalSize = Int(5 + dataSize)
            guard buffer.count >= totalSize else { break }

            let statusCode = buffer[0]
            let data = buffer.subdata(in: 5..<totalSize)

            switch statusCode {
            case 0: // Final result
                latestStatus = .completed(data)
            case 1: // Status update
                if let statusText = String(data: data, encoding: .utf8) {
                    latestStatus = .progress(statusText)
                }
            case 2: // Error
                if let errorText = String(data: data, encoding: .utf8) {
                    latestStatus = .error(errorText)
                }
            case 3: // Queue position
                if let queuePos = String(data: data, encoding: .utf8) {
                    latestStatus = .pending(queuePosition: queuePos)
                }
            case 4: // Pending without queue position
                latestStatus = .pending(queuePosition: nil)
            default:
                break
            }

            buffer.removeSubrange(0..<totalSize)
        }

        return latestStatus
    }
}
