//
//  Data+Extensions.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 16.11.25.
//

import Foundation
import SwiftUI
import Logging

private let logger = Logger(label: "com.qalti.DataExtensions")

extension Data {

    /// Initializes `Data` from a string that is either a Data URL or a raw Base64 encoding.
    ///
    /// This initializer is robust and handles two common formats for image data:
    /// 1. Standard Data URL: "data:image/jpeg;base64,..."
    /// 2. Raw Base64 String: "..."
    ///
    /// It returns `nil` if the string cannot be decoded into valid image data.
    /// - Parameter imageDataString: The string containing the image data.
    init?(fromImageDataString imageDataString: String) {
        // Path 1: Handle the standard Data URL format.
        if imageDataString.hasPrefix("data:image/"), let commaIndex = imageDataString.firstIndex(of: ",") {
            let base64String = imageDataString.suffix(from: imageDataString.index(after: commaIndex))
            if let data = Data(base64Encoded: String(base64String)) {
                self = data
                return
            }
        }

        // Path 2: Handle a raw Base64 string as a fallback.
        // The `PlatformImage` check ensures the data is a valid image before we succeed.
        if let data = Data(base64Encoded: imageDataString), PlatformImage(data: data) != nil {
            logger.warning("Initializing Data from a raw Base64 string. The data URL prefix may be missing.")
            self = data
            return
        }

        // If neither format works, initialization fails.
        if !imageDataString.isEmpty {
            logger.error("Failed to initialize Data. The string was not a valid Data URL or raw Base64 image string.", metadata: ["string_prefix": .string(String(imageDataString.prefix(30)))])
        }
        return nil
    }
}
