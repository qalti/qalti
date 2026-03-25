//
//  Action.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 04.03.2025.
//

import Foundation

// For test report compatibility
struct Action: Decodable {

    struct TapVisualisation: Equatable, Codable {
        struct TapLocation: Equatable, Codable {
            let x: Int
            let y: Int
        }
        let originalTap: TapLocation
        let commandTap: TapLocation
    }
    
    struct ZoomVisualisation: Equatable, Codable {
        let x: Int
        let y: Int
        let scale: Double
    }

    enum CodingKeys: String, CodingKey {
        case action
        case parsedAction
        case startImage
        case endImage
        case elementImage
    }

    let id = UUID()
    var action: String
    var parsedAction: String?
    var lastParsedAction: String?
    var isLoading = false
    var startImage: PlatformImage?
    var endImage: PlatformImage?
    let elementImage: PlatformImage?
    var referencedSteps: [UUID] = []
    var tapVisualisation: TapVisualisation? = nil
    var zoomVisualisation: ZoomVisualisation? = nil
    var warning: String? = nil

    init(
        action: String, 
        parsedAction: String? = nil, 
        lastParsedAction: String? = nil, 
        isLoading: Bool = false, 
        startImage: PlatformImage? = nil, 
        endImage: PlatformImage? = nil, 
        elementImage: PlatformImage? = nil, 
        referencedSteps: [UUID] = [],
        tapVisualisation: TapVisualisation? = nil,
        zoomVisualisation: ZoomVisualisation? = nil,
        warning: String? = nil
    ) {
        self.action = action
        self.parsedAction = parsedAction
        self.lastParsedAction = lastParsedAction
        self.isLoading = isLoading
        self.startImage = startImage
        self.endImage = endImage
        self.elementImage = elementImage
        self.tapVisualisation = tapVisualisation
        self.zoomVisualisation = zoomVisualisation
        self.warning = warning
        self.referencedSteps = referencedSteps
    }
    

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        parsedAction = try container.decodeIfPresent(String.self, forKey: .parsedAction)
        if let startImageData = try container.decodeIfPresent(Data.self, forKey: .startImage) {
            startImage = PlatformImage(data: startImageData)
        } else {
            startImage = nil
        }
        
        if let endImageData = try container.decodeIfPresent(Data.self, forKey: .endImage) {
            endImage = PlatformImage(data: endImageData)
        } else {
            endImage = nil
        }
        
        if let elementImageData = try container.decodeIfPresent(Data.self, forKey: .elementImage) {
            elementImage = PlatformImage(data: elementImageData)
        } else {
            elementImage = nil
        }
    }
}
