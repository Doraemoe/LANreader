//
// Created on 14/9/20.
//

import Foundation

class Selector<B: Equatable, F: Equatable, R> {
    private var lastBase: B
    private var lastFilter: F
    private var lastResult: R

    init(initBase: B, initFilter: F, initResult: R) {
        self.lastBase = initBase
        self.lastFilter = initFilter
        self.lastResult = initResult
    }

    func select(base: B,
                filter: F,
                selector: @escaping (B, F) -> R) -> R {
        if base != lastBase || filter != lastFilter {
            self.lastBase = base
            self.lastFilter = filter
            self.lastResult = selector(base, filter)
        }
        return lastResult
    }
}
