//
//  PlatformImage.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 04.03.2025.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif


#if os(macOS)
extension PlatformImage {
    func jpegData(compressionQuality: CGFloat = 0.8) -> Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [.compressionFactor: NSNumber(value: compressionQuality)])
    }

    func resized(to newSize: CGSize) -> PlatformImage {
        // Ensure exact pixel dimensions using CoreGraphics (avoid Retina scale ambiguity)
        let targetWidth = max(1, Int(round(newSize.width)))
        let targetHeight = max(1, Int(round(newSize.height)))

        guard let sourceCG = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return self
        }

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self
        }

        context.interpolationQuality = .high
        context.draw(sourceCG, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let outCG = context.makeImage() else { return self }
        return PlatformImage(cgImage: outCG, size: NSSize(width: targetWidth, height: targetHeight))
    }

    func cropped(to rect: CGRect) -> PlatformImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        guard let croppedImage = cgImage.cropping(to: rect) else { return nil }
        return PlatformImage(cgImage: croppedImage, size: rect.size)
    }

    convenience init?(sfsymbol: String) {
        self.init(systemSymbolName: sfsymbol, accessibilityDescription: nil)
    }
    
    convenience init(cgImage: CGImage, scale: CGFloat) {
        let size = NSSize(
            width: CGFloat(cgImage.width) * scale,
            height: CGFloat(cgImage.height) * scale
        )
        self.init(cgImage: cgImage, size: size)
    }
}
#else

extension PlatformImage {
    func resized(to newSize: CGSize) -> PlatformImage {
        // Ensure exact pixel dimensions; use CoreGraphics and set resulting UIImage scale to 1.0
        let targetWidth = max(1, Int(round(newSize.width)))
        let targetHeight = max(1, Int(round(newSize.height)))

        guard let sourceCG = self.cgImage else { return self }

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self
        }

        context.interpolationQuality = .high
        context.draw(sourceCG, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let outCG = context.makeImage() else { return self }
        return PlatformImage(cgImage: outCG, scale: 1.0, orientation: .up)
    }

    func cropped(to rect: CGRect) -> PlatformImage? {
        guard let cgImage = self.cgImage else { return nil }
        guard let croppedImage = cgImage.cropping(to: rect) else { return nil }
        return PlatformImage(cgImage: croppedImage)
    }

    convenience init?(sfsymbol: String) {
        self.init(systemName: sfsymbol)
    }
    
    convenience init(cgImage: CGImage, scale: CGFloat) {
        self.init(cgImage: cgImage, scale: 1.0 / scale, orientation: .up)
    }
}
#endif

extension Image {

    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }

}

extension PlatformImage {

    func resized(toHeight maxHeight: Int) -> PlatformImage {
        let maxHeightFloat = CGFloat(maxHeight)
        let newSize = CGSize(
            width: maxHeightFloat * size.width / size.height,
            height: maxHeightFloat
        )
        return resized(to: newSize)
    }
    
    /// Draw coordinate markers on the image for debugging purposes
    /// - Parameter coordinates: Array of (x, y) coordinate pairs to mark
    /// - Returns: New image with markers drawn
    func withCoordinateMarkers(_ coordinates: [(x: Int, y: Int)]) -> PlatformImage {
        let markerSize = max(size.width, size.height) * 0.035
        let radius = markerSize / 2
        
        let newImage = PlatformImage(size: size)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        
        // Draw the original image
        draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        
        // Set up drawing context
        guard let context = NSGraphicsContext.current?.cgContext else { return self }
        
        // Draw markers for each coordinate
        for coord in coordinates {
            let centerX = CGFloat(coord.x)
            let centerY = size.height - CGFloat(coord.y) // Flip Y coordinate for macOS
            
            // Draw circle outline in red
            context.setStrokeColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
            context.setLineWidth(5.0)
            context.strokeEllipse(in: CGRect(
                x: centerX - radius,
                y: centerY - radius,
                width: markerSize,
                height: markerSize
            ))
            
            // Draw center point
            context.setFillColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
            let pointRadius: CGFloat = 5.0
            context.fillEllipse(in: CGRect(
                x: centerX - pointRadius,
                y: centerY - pointRadius,
                width: pointRadius * 2,
                height: pointRadius * 2
            ))
        }
        
        return newImage
    }
    
    /// Draw a zoom marker on the image for debugging purposes
    /// - Parameter coordinate: The (x, y) center point for the zoom gesture
    /// - Parameter scale: The scale factor, used to determine arrow direction (>1 for zoom-in, <1 for zoom-out)
    /// - Returns: New image with zoom markers drawn
    func withZoomMarker(coordinate: (x: Int, y: Int), scale: Double) -> PlatformImage {
        let maxRadius = max(size.width, size.height) * 0.05
        let thickness: CGFloat = 5.0
        
        let newImage = PlatformImage(size: size)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        
        // Draw the original image
        draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        
        // --- Drawing Setup ---
        guard let context = NSGraphicsContext.current?.cgContext else { return self }
        
        // Use a consistent "Qalti Orange" color for interaction markers
        let markerColor = CGColor(red: 1.0, green: 0.35, blue: 0.0, alpha: 1.0)
        
        let centerX = CGFloat(coordinate.x)
        let centerY = size.height - CGFloat(coordinate.y) // Flip Y for macOS context
        
        // --- 1. Draw Concentric Circles for Visibility ---
        let circleRadii = [maxRadius * 0.5, maxRadius]
        let circleAlphas: [CGFloat] = [0.4, 0.2] // Outer circle is more transparent
        
        for (i, radius) in circleRadii.enumerated() {
            let circleColor = markerColor.copy(alpha: circleAlphas[i])
            context.setFillColor(circleColor!)
            let circleRect = CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: circleRect)
        }
        
        // --- 2. Draw Directional Arrows ---
        context.setStrokeColor(markerColor)
        context.setLineWidth(thickness)
        
        func drawArrow(from startPoint: CGPoint, to endPoint: CGPoint) {
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
            
            // Arrowhead math
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let arrowheadLength = thickness * 3.0
            
            let arrowPoint1 = CGPoint(
                x: endPoint.x - arrowheadLength * cos(angle - .pi / 6),
                y: endPoint.y - arrowheadLength * sin(angle - .pi / 6)
            )
            let arrowPoint2 = CGPoint(
                x: endPoint.x - arrowheadLength * cos(angle + .pi / 6),
                y: endPoint.y - arrowheadLength * sin(angle + .pi / 6)
            )
            
            context.move(to: endPoint)
            context.addLine(to: arrowPoint1)
            context.move(to: endPoint)
            context.addLine(to: arrowPoint2)
            context.strokePath()
        }
        
        let isZoomIn = scale > 1.0
        let arrowStartOffset = maxRadius * 0.6 // Arrows start from the edge of the inner circle
        
        let start1 = CGPoint(x: centerX - arrowStartOffset, y: centerY - arrowStartOffset)
        let end1 = CGPoint(x: centerX - maxRadius, y: centerY - maxRadius)
        
        let start2 = CGPoint(x: centerX + arrowStartOffset, y: centerY + arrowStartOffset)
        let end2 = CGPoint(x: centerX + maxRadius, y: centerY + maxRadius)
        
        if isZoomIn {
            // Arrows point outwards
            drawArrow(from: start1, to: end1)
            drawArrow(from: start2, to: end2)
        } else {
            // Arrows point inwards
            drawArrow(from: end1, to: start1)
            drawArrow(from: end2, to: start2)
        }
        
        return newImage
    }
}
