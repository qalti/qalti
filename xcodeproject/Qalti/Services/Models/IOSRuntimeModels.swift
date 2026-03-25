//
//  IOSRuntimeModels.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

// MARK: - Error Enum

enum IOSRuntimeError: Error, LocalizedError {
    /// The virtual network tunnel from Mac to iPhone is broken.
    case ghostTunnelDetected(ip: String, udid: String)
    /// A shell command took too long to execute.
    case commandTimedOut
    /// The current platform (e.g., non-macOS) does not support this operation.
    case unsupportedPlatform
    /// Failed to parse a response from a tool or command.
    case responseParseFailed(description: String)

    var errorDescription: String? {
        switch self {
        case .ghostTunnelDetected(let ip, let udid):
            return "Network Tunnel Issue: Your Mac can see that device \(udid) is assigned IP \(ip), but it cannot create a network route to it. This is often caused by a VPN or a stuck system service."
        case .commandTimedOut:
            return "A system command timed out."
        case .unsupportedPlatform:
            return "This operation is not supported on the current platform."
        case .responseParseFailed(let description):
            return "Failed to parse response: \(description)"
        }
    }
}

// MARK: - Data Structures

enum Permission: String {
    case all, calendar, contacts, location, photos, microphone, motion, reminders, siri
    case contactsLimited = "contacts-limited"
    case locationalways = "location-always"
    case photosAdd = "photos-add"
    case mediaLibrary = "media-library"
}

struct IOSRuntimeResponse {
    let error: String?
    let image: PlatformImage?
    let imageURL: URL?

    init(error: String? = nil, image: PlatformImage? = nil, imageURL: URL? = nil) {
        self.error = error
        self.image = image
        self.imageURL = imageURL
    }

    func withScreenshot(image: PlatformImage?, imageURL: URL?) -> IOSRuntimeResponse {
        return IOSRuntimeResponse(error: error, image: image, imageURL: imageURL)
    }

    var imageJpegData: Data? { image?.jpegData() }
}
