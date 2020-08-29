//Created 29/8/20

import Foundation

enum PageControl: String, CaseIterable, Identifiable {
    case next
    case previous
    case navigation
    
    var id: String { self.rawValue }
}
