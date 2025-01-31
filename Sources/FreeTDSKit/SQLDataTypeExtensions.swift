//
//  SQLDataTypeExtensions.swift
//  FreeTDSKit
//
//  Created by David Oliver on 1/22/25.
//

import Foundation

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var mutableSelf = self
        NSDecimalRound(&result, &mutableSelf, scale, .plain)
        return result
    }
}
