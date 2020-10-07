//Created 7/10/20

import Foundation

class FileUtils {
    static func readJsonFile(filename: String) throws -> String {
        let path = Bundle(for: FileUtils.self).path(forResource: filename, ofType: "json")
        do {
            return try String(contentsOfFile: path!, encoding: String.Encoding.utf8)
        } catch {
            throw error
        }
    }
}
