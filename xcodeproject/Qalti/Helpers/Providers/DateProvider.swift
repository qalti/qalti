//
//  DateProvider.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation

protocol DateProvider {
    func now() -> Date
}

struct SystemDateProvider: DateProvider {
    func now() -> Date {
        return Date()
    }
}
