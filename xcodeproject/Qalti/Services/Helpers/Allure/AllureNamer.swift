//
//  AllureNamer.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 03.12.25.
//

import Foundation

enum AllureNamer {

    /// Generates a standardized, readable name for a screenshot attachment.
    ///
    /// - If there is only one image in the message, it returns "Screenshot after Step X".
    /// - If there are multiple images, it returns "Screenshot after Step X (Y)".
    ///
    /// - Parameters:
    ///   - step: The overall step number in the test run.
    ///   - imageIndex: The zero-based index of the image within its message.
    ///   - totalImagesInMessage: The total number of images in the message.
    static func screenshotName(step: Int, imageIndex: Int, totalImagesInMessage: Int) -> String {
        if totalImagesInMessage > 1 {
            return "Screenshot after Step \(step) (\(imageIndex + 1))"
        } else {
            return "Screenshot after Step \(step)"
        }
    }
}
