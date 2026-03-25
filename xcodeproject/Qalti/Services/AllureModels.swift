//
//  AllureModels.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 27.11.25.
//

import Foundation

// MARK: - Allure Enums

enum AllureStatus: String, Codable {
    case passed
    case failed
    case broken
    case skipped
    case unknown
}

// MARK: - Allure Data Structures

struct AllureTestResult: Codable {
    let uuid: String
    let historyId: String?
    let testCaseId: String?
    let fullName: String
    let name: String
    let status: AllureStatus
    let statusDetails: AllureStatusDetails?
    let description: String?
    let start: Int64
    let stop: Int64
    let steps: [AllureStep]
    let labels: [AllureLabel]
    let links: [AllureLink]
    let attachments: [AllureAttachment]?

    struct AllureStep: Codable {
        let name: String
        let status: AllureStatus
        let statusDetails: AllureStatusDetails?
        let start: Int64
        let stop: Int64
        let attachments: [AllureAttachment]?
        let parameters: [AllureParameter]?
    }

    struct AllureStatusDetails: Codable {
        let message: String?
        let trace: String?
    }

    struct AllureLabel: Codable {
        let name: String
        let value: String
    }

    struct AllureLink: Codable {
        let type: String
        let name: String
        let url: String
    }

    struct AllureAttachment: Codable {
        let name: String
        let source: String
        let type: String
    }

    struct AllureParameter: Codable {
        let name: String
        let value: String
    }
}
