//
//  HierarchyOverlay.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 04.03.2025.
//

import SwiftUI

/// Represents a UI element in the hierarchy
struct UIElement: Identifiable, Equatable {
    let id = UUID()
    let depth: Int
    let type: String
    let frame: CGRect
    let label: String?
    let identifier: String?
    let address: String
    let parentId: UUID?
    
    var description: String {
        var desc = "\(type)"
        if let label = label, !label.isEmpty {
            desc += " '\(label)'"
        }
        if let identifier = identifier, !identifier.isEmpty {
            desc += " (id: \(identifier))"
        }
        return desc
    }
}

/// ViewModel that handles the UI hierarchy polling and element detection
class HierarchyViewModel: ObservableObject {
    @Published var elements: [UIElement] = []
    @Published var referenceSize: CGSize = .zero
    @Published var selectedElement: UIElement?
    
    private var runtime: IOSRuntime?
    private var timer: Timer?
    
    func setup(with runtime: IOSRuntime) {
        self.runtime = runtime
        startPolling()
    }
    
    func startPolling() {
        stopPolling()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateHierarchy()
        }
        
        // Initial update
        updateHierarchy()
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateHierarchy() {
        guard let runtime = runtime else { return }
        
        runtime.getHierarchy { [weak self] hierarchyText in
            guard let self = self, let hierarchyText = hierarchyText else { return }
            
            DispatchQueue.main.async {
                self.parseHierarchy(hierarchyText)
            }
        }
    }
    
    private func parseHierarchy(_ hierarchyText: String) {
        var parsedElements: [UIElement] = []
        let lines = hierarchyText.components(separatedBy: .newlines)

        var firstWindowSizeParsed: Bool = false
        
        // Track the last element at each depth level
        var depthToElementMap: [Int: UIElement] = [:]

        // Skip the first two lines as they're headers
        for line in lines.dropFirst(2) {
            if let element = parseElementLine(line, depthToElementMap: depthToElementMap) {
                parsedElements.append(element)
                
                // Store this element as the last one seen at its depth
                depthToElementMap[element.depth] = element
                
                // Get reference size from the application element
                if element.type.starts(with: "Window") {
                    if firstWindowSizeParsed == false {
                        self.referenceSize = element.frame.size
                        firstWindowSizeParsed = true
                    } else {
                        // Dont' parse elements from different windows
                        break
                    }
                }
            }
        }
        
        self.elements = parsedElements
    }
    
    private func parseElementLine(_ line: String, depthToElementMap: [Int: UIElement]) -> UIElement? {
        // Count leading spaces to determine depth
        let depth = line.prefix(while: { $0 == " " }).count / 2  // Assuming 2 spaces per level
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        // Parse the element type
        guard let typeEndIndex = trimmedLine.firstIndex(of: ",") else { return nil }
        let type = String(trimmedLine[..<typeEndIndex])
        
        // Parse the memory address
        let addressStart = trimmedLine.index(after: typeEndIndex)
        guard let addressEndIndex = trimmedLine[addressStart...].firstIndex(of: ",") else { return nil }
        let address = String(trimmedLine[addressStart..<addressEndIndex]).trimmingCharacters(in: .whitespaces)
        
        // Extract frame coordinates
        var frame = CGRect.zero
        if let frameStart = trimmedLine.range(of: "{{")?.upperBound,
           let frameEnd = trimmedLine.range(of: "}}")?.lowerBound {
            let frameString = String(trimmedLine[frameStart..<frameEnd])
            frame = parseFrame(frameString)
        }
        
        // Extract label if present
        var label: String? = nil
        if let labelRange = trimmedLine.range(of: "label: '") {
            let labelStart = labelRange.upperBound
            // Find the closing quote that's not escaped
            var searchIndex = labelStart
            while searchIndex < trimmedLine.endIndex {
                if trimmedLine[searchIndex] == "'" && 
                   (searchIndex == trimmedLine.startIndex || trimmedLine[trimmedLine.index(before: searchIndex)] != "\\") {
                    label = String(trimmedLine[labelStart..<searchIndex])
                    break
                }
                searchIndex = trimmedLine.index(after: searchIndex)
            }
        }
        
        // Extract identifier if present
        var identifier: String? = nil
        if let idRange = trimmedLine.range(of: "identifier: '") {
            let idStart = idRange.upperBound
            var searchIndex = idStart
            while searchIndex < trimmedLine.endIndex {
                if trimmedLine[searchIndex] == "'" && 
                   (searchIndex == trimmedLine.startIndex || trimmedLine[trimmedLine.index(before: searchIndex)] != "\\") {
                    identifier = String(trimmedLine[idStart..<searchIndex])
                    break
                }
                searchIndex = trimmedLine.index(after: searchIndex)
            }
        }
        
        // Get the parent element - which is the element at depth - 1
        let parentId = depth > 0 ? depthToElementMap[depth - 1]?.id : nil
        
        return UIElement(
            depth: depth,
            type: type,
            frame: frame,
            label: label,
            identifier: identifier,
            address: address,
            parentId: parentId
        )
    }
    
    private func parseFrame(_ frameString: String) -> CGRect {
        let components = frameString.components(separatedBy: "}, {")
        guard components.count == 2 else { return .zero }
        
        let originStr = components[0].trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        let sizeStr = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        
        let originComponents = originStr.components(separatedBy: ", ")
        let sizeComponents = sizeStr.components(separatedBy: ", ")
        
        guard originComponents.count == 2,
              sizeComponents.count == 2,
              let x = Double(originComponents[0]),
              let y = Double(originComponents[1]),
              let width = Double(sizeComponents[0]),
              let height = Double(sizeComponents[1])
        else {
            return .zero
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func parseSizeFromFrameString(_ frameString: String) -> CGSize? {
        let components = frameString.components(separatedBy: "}, {")
        guard components.count == 2 else { return nil }
        
        let sizeStr = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        let sizeComponents = sizeStr.components(separatedBy: ", ")
        
        guard sizeComponents.count == 2,
              let width = Double(sizeComponents[0]),
              let height = Double(sizeComponents[1])
        else {
            return nil
        }
        
        return CGSize(width: width, height: height)
    }
    
    func findElementAt(normalizedPoint: CGPoint) -> UIElement? {
        guard !referenceSize.width.isZero && !referenceSize.height.isZero else { return nil }
        
        // Convert normalized point to device coordinates
        let devicePoint = CGPoint(
            x: normalizedPoint.x * referenceSize.width,
            y: normalizedPoint.y * referenceSize.height
        )
        
        // Find all elements that contain this point
        let containingElements = elements.filter { element in
            if element.type.starts(with: "Window") { return false }

            switch element.type {
            case "Other", "ScrollView", "CollectionView", "LayoutArea", "LayoutItem", "Sheet", "Table":
                return false
            default:
                return element.frame.contains(devicePoint)
            }
        }

        let lastElement = containingElements.last

        if let lastElement,
            lastElement.type == "Image" || lastElement.type == "StaticText",
            let parentID = lastElement.parentId
        {
            let parent = elements.first { $0.id == parentID }
            if let parent, parent.type == "Button" || parent.type == "TextField" {
                return parent
            }

            if let grandParentID = parent?.parentId {
                let grandParent = elements.first { $0.id == grandParentID }
                if let grandParent, grandParent.type == "Button" || grandParent.type == "TextField" {
                    return grandParent
                }
            }
        }
        
        // Return the closest to the  element
        return containingElements.last
    }
    
    func updateSelectedElement(at mousePosition: CGPoint, viewSize: CGSize) {
        // Normalize mouse position to 0-1 range
        let normalizedPoint = CGPoint(
            x: mousePosition.x / viewSize.width,
            y: mousePosition.y / viewSize.height
        )
        
        selectedElement = findElementAt(normalizedPoint: normalizedPoint)
    }
}

struct HierarchyOverlay: View {
    @StateObject private var viewModel = HierarchyViewModel()
    @State private var mouseLocation: CGPoint = .zero
    @State private var viewSize: CGSize = .zero
    @Binding var selectedElement: UIElement?
    @Binding var referenceSize: CGSize
    let runtime: IOSRuntime
    
    // Initialize with default binding value
    init(runtime: IOSRuntime, selectedElement: Binding<UIElement?>, referenceSize: Binding<CGSize>) {
        self.runtime = runtime
        self._selectedElement = selectedElement
        self._referenceSize = referenceSize
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        viewModel.setup(with: runtime)
                        viewSize = geometry.size
                    }
                    .legacy_onChange(of: geometry.size) { newSize in
                        viewSize = newSize
                    }
            }
            
            // Highlight rectangle for selected element
            if let selectedElement = viewModel.selectedElement, 
               !viewModel.referenceSize.width.isZero, 
               !viewModel.referenceSize.height.isZero 
            {
                let convertedRect = convertRectToViewCoordinates(
                    selectedElement.frame,
                    fromReferenceSize: viewModel.referenceSize,
                    toViewSize: viewSize
                )
                
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .frame(
                        width: convertedRect.width + 8,
                        height: convertedRect.height + 8
                    )
                    .position(
                        x: convertedRect.midX,
                        y: convertedRect.midY
                    )
            }
            
            VStack(alignment: .leading) {
                Spacer()
                
                if let selectedElement = viewModel.selectedElement {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Element: \(selectedElement.description)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding()
                }
            }
        }
        .legacy_onChange(of: viewModel.selectedElement) { newValue in
            selectedElement = newValue
        }
        .legacy_onChange(of: viewModel.referenceSize) { newValue in
            referenceSize = newValue
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                mouseLocation = location
                viewModel.updateSelectedElement(at: location, viewSize: viewSize)
            case .ended:
                break
            }
        }
    }
    
    private func convertRectToViewCoordinates(_ rect: CGRect, fromReferenceSize: CGSize, toViewSize: CGSize) -> CGRect {
        // Scale factors for width and height
        let widthScale = toViewSize.width / fromReferenceSize.width
        let heightScale = toViewSize.height / fromReferenceSize.height
        
        // Convert and scale the rectangle
        return CGRect(
            x: rect.origin.x * widthScale,
            y: rect.origin.y * heightScale,
            width: rect.width * widthScale,
            height: rect.height * heightScale
        )
    }
}
