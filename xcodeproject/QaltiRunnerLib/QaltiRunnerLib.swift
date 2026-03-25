import Network
import UniformTypeIdentifiers
import os
import UIKit

// Bridge helpers to call XCTest UI Testing APIs via Objective-C runtime without importing XCTest
final class XCTestBridge {

    private static var tokens: [AnyObject] = []

    // MARK: - Screenshots

    static func screenshotJPEG(highQuality: Bool = false) -> Data? {
        guard let screenClass = NSClassFromString("XCUIScreen") as? NSObject.Type else { return nil }
        let mainSelector = NSSelectorFromString("mainScreen")
        guard let screenAny = screenClass.perform(mainSelector)?.takeUnretainedValue() as? NSObject else { return nil }

        // Prepare encoding
        guard let encodingClass = NSClassFromString("XCTImageEncoding") as? NSObject.Type else { return nil }
        guard let encoding = (encodingClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else { return nil }
        _ = encoding.perform(NSSelectorFromString("initWithUniformTypeIdentifier:compressionQuality:"), with: UTType.jpeg.identifier as NSString, with: NSNumber(value: highQuality ? 0.95 : 0.0))

        // Call screenshotWithEncoding:options:
        let screenshotSelector = NSSelectorFromString("screenshotWithEncoding:options:")
        guard screenAny.responds(to: screenshotSelector) else { return nil }
        guard let screenshotRef = screenAny.perform(screenshotSelector, with: encoding, with: nil)?.takeUnretainedValue() else { return nil }

        // Extract data
        let screenshotObj = screenshotRef as AnyObject
        let internalImage = (screenshotObj.value(forKey: "internalImage") as AnyObject?)
        let data = internalImage?.value(forKey: "data") as? Data
        return data
    }

    // MARK: - Timeout

    static func setApplicationStateTimeout(_ timeout: TimeInterval) {
        typealias XCTSetApplicationStateTimeout = @convention(c) (Double) -> Int32
        guard let handle = dlopen("/usr/lib/libXCTestSwiftSupport.dylib", RTLD_NOW) else {
            AppLogger.error("Failed to open libXCTestSwiftSupport.dylib")
            return
        }
        guard let symbol = dlsym(handle, "_XCTSetApplicationStateTimeout") else {
            AppLogger.error("Failed to find symbol _XCTSetApplicationStateTimeout")
            return
        }
        let function = unsafeBitCast(symbol, to: XCTSetApplicationStateTimeout.self)
        let result = function(timeout)
        AppLogger.info("Result of _XCTSetApplicationStateTimeout: \(result)")
    }

    // MARK: - Applications

    static func application(bundleIdentifier: String) -> NSObject? {
        guard let appClass = NSClassFromString("XCUIApplication") as? NSObject.Type else { return nil }
        guard let app = (appClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else { return nil }
        let initSel = NSSelectorFromString("initWithBundleIdentifier:")
        if app.responds(to: initSel) {
            _ = app.perform(initSel, with: bundleIdentifier as NSString)
            return app
        }
        return nil
    }

    static func applicationUnderTest() -> NSObject? {
        guard let appClass = NSClassFromString("XCUIApplication") as? NSObject.Type else { return nil }
        return appClass.init()
    }

    static func launch(_ app: NSObject, launchArguments: [String]? = nil, launchEnvironment: [String: String]? = nil) {
        let argumentsSelector = NSSelectorFromString("setLaunchArguments:")
        if let launchArguments, app.responds(to: argumentsSelector) {
            _ = app.perform(argumentsSelector, with: launchArguments as NSArray)
        } else if let launchArguments, !launchArguments.isEmpty {
            app.setValue(launchArguments, forKey: "launchArguments")
        }

        if let launchEnvironment, !launchEnvironment.isEmpty {
            let environmentSelector = NSSelectorFromString("setLaunchEnvironment:")
            if app.responds(to: environmentSelector) {
                _ = app.perform(environmentSelector, with: launchEnvironment as NSDictionary)
            } else {
                app.setValue(launchEnvironment, forKey: "launchEnvironment")
            }
        }

        _ = app.perform(NSSelectorFromString("launch"))
    }

    static func activate(_ app: NSObject) {
        _ = app.perform(NSSelectorFromString("activate"))
    }

    static func state(_ app: NSObject) -> Int? {
        return app.value(forKey: "state") as? Int
    }

    static func isRunningForeground(_ app: NSObject) -> Bool {
        // XCUIApplicationState.runningForeground == 4
        guard let state = state(app) else { return true }
        return state == 4
    }

    // MARK: - Device / System

    static func openURL(_ url: URL) {
        guard let deviceClass = NSClassFromString("XCUIDevice") as? NSObject.Type else { return }
        let shared: AnyObject?
        if deviceClass.responds(to: NSSelectorFromString("sharedDevice")) {
            shared = deviceClass.perform(NSSelectorFromString("sharedDevice"))?.takeUnretainedValue()
        } else {
            shared = deviceClass.perform(NSSelectorFromString("shared"))?.takeUnretainedValue()
        }
        guard let device = shared as? NSObject else { return }
        let system = device.value(forKey: "system") as AnyObject?
        if let sys = system as? NSObject {
            if sys.responds(to: NSSelectorFromString("openURL:")) {
                _ = sys.perform(NSSelectorFromString("openURL:"), with: url as NSURL)
            } else if sys.responds(to: NSSelectorFromString("open:")) {
                _ = sys.perform(NSSelectorFromString("open:"), with: url as NSURL)
            }
        }
    }

    // MARK: - Keyboard / Text

    private static var cachedActiveField: NSObject? = nil

    static func hasKeyboardFocus(_ element: NSObject) -> Bool {
        return (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    static func typeText(_ element: NSObject, text: String) {
        _ = element.perform(NSSelectorFromString("typeText:"), with: text as NSString)
    }

    static func clearText(_ element: NSObject) {
        guard let stringValue = element.value(forKey: "value") as? String else { return }
        if let placeholderString = element.value(forKey: "placeholderValue") as? String, placeholderString == stringValue {
            return
        }
        // Best-effort: delete character key for UI tests
        let deleteKey = "\u{8}"
        let deleteString = String(repeating: deleteKey, count: stringValue.count)
        typeText(element, text: deleteString)
    }

    static func keyboardsCount(_ app: NSObject) -> Int {
        guard let keyboards = (app.value(forKey: "keyboards") as AnyObject?) else { return 0 }
        return (keyboards.value(forKey: "count") as? Int) ?? 0
    }

    static func findActiveTextField(in app: NSObject) -> NSObject? {
        // Use cached field if it still has focus
        if let cached = cachedActiveField, hasKeyboardFocus(cached) {
            return cached
        }

        let queryNames = ["textFields", "secureTextFields", "textViews", "searchFields"]
        for name in queryNames {
            guard let query = (app.value(forKey: name) as AnyObject?) else { continue }
            let elements = (query.value(forKey: "allElementsBoundByIndex") as? [NSObject]) ?? []
            for element in elements {
                if hasKeyboardFocus(element) {
                    cachedActiveField = element
                    return element
                }
            }
        }
        cachedActiveField = nil
        return nil
    }

    // MARK: - Active Application Detection

    private static func springboard() -> NSObject? {
        return application(bundleIdentifier: "com.apple.springboard")
    }

    static func activeApplicationBySpringBoardCard() -> NSObject? {
        guard let sb = springboard() else { return nil }
        guard let otherElements = (sb.value(forKey: "otherElements") as AnyObject?) else { return nil }

        // Find active scene card via predicate on identifier: "card:*sceneID:*"
        let predicate = NSPredicate(format: "identifier LIKE %@", "card:*sceneID:*")

        let matchingPredicateSel = NSSelectorFromString("matchingPredicate:")
        let elementMatchingPredicateSel = NSSelectorFromString("elementMatchingPredicate:")
        let firstMatchSel = NSSelectorFromString("firstMatch")
        let elementBoundByIndexSel = NSSelectorFromString("elementBoundByIndex:")

        var activeScene: NSObject? = nil

        if (otherElements as AnyObject).responds(to: matchingPredicateSel),
           let filteredQuery = (otherElements.perform(matchingPredicateSel, with: predicate)?.takeUnretainedValue() as? NSObject) {
            if filteredQuery.responds(to: firstMatchSel) {
                activeScene = filteredQuery.value(forKey: "firstMatch") as? NSObject
            }
            if activeScene == nil, filteredQuery.responds(to: elementBoundByIndexSel) {
                activeScene = filteredQuery.perform(elementBoundByIndexSel, with: NSNumber(value: 0))?.takeUnretainedValue() as? NSObject
            }
        } else if (otherElements as AnyObject).responds(to: elementMatchingPredicateSel) {
            let element = otherElements.perform(elementMatchingPredicateSel, with: predicate)?.takeUnretainedValue() as? NSObject
            if let el = element {
                if el.responds(to: firstMatchSel) {
                    activeScene = el.value(forKey: "firstMatch") as? NSObject
                } else {
                    activeScene = el
                }
            }
        }

        guard let scene = activeScene, (scene.value(forKey: "exists") as? Bool) == true else { return nil }
        let identifier = scene.value(forKey: "identifier") as? String ?? ""
        if let range = identifier.range(of: ":sceneID:") {
            let prefix = String(identifier[..<range.lowerBound])
            let bundleId = prefix.replacingOccurrences(of: "card:", with: "")
            AppLogger.info("Using app with bundle ID: \(bundleId)")
            if let app = application(bundleIdentifier: bundleId) { return app }
        }
        return nil
    }

    static func focusedOrActiveApp() -> NSObject? {
        if let active = activeApplicationBySpringBoardCard(), isRunningForeground(active) { return active }
        return nil
    }

    // MARK: - Coordinates & Gestures

    static func rootCoordinate(of element: NSObject) -> NSObject? {
        let selector = NSSelectorFromString("coordinateWithNormalizedOffset:")
        guard element.responds(to: selector) else { return nil }
        typealias CoordWithNormalizedOffsetFn = @convention(c) (AnyObject, Selector, CGVector) -> Unmanaged<AnyObject>?
        let imp = element.method(for: selector)
        let fn = unsafeBitCast(imp, to: CoordWithNormalizedOffsetFn.self)
        return fn(element, selector, CGVector(dx: 0, dy: 0))?.takeUnretainedValue() as? NSObject
    }

    static func coordinate(_ coordinate: NSObject, withOffset offset: CGVector) -> NSObject? {
        let selector = NSSelectorFromString("coordinateWithOffset:")
        guard coordinate.responds(to: selector) else { return nil }
        typealias CoordWithOffsetFn = @convention(c) (AnyObject, Selector, CGVector) -> Unmanaged<AnyObject>?
        let imp = coordinate.method(for: selector)
        let fn = unsafeBitCast(imp, to: CoordWithOffsetFn.self)
        return fn(coordinate, selector, offset)?.takeUnretainedValue() as? NSObject
    }
    
    private static func descendants(of element: NSObject, matching typeIdentifier: Int) -> [NSObject] {
        let descendantsSel = NSSelectorFromString("descendantsMatchingType:")
        guard element.responds(to: descendantsSel) else { return [] }
        
        typealias DescendantsFn = @convention(c) (AnyObject, Selector, Int) -> Unmanaged<AnyObject>?
        let imp = element.method(for: descendantsSel)
        let fn = unsafeBitCast(imp, to: DescendantsFn.self)
        
        guard let query = fn(element, descendantsSel, typeIdentifier)?.takeUnretainedValue() as? NSObject else { return [] }
        
        // The `allElementsBoundByIndex` property returns an array of all elements in the query.
        return query.value(forKey: "allElementsBoundByIndex") as? [NSObject] ?? []
    }
    
    static func findSmallestElementAtPoint(in rootElement: NSObject, point: CGPoint) -> NSObject? {
        // XCUIElementType.any has an integer value of 0.
        let allDescendants = descendants(of: rootElement, matching: 0)
        
        var matchingElementsAndFrames: [(element: NSObject, frame: CGRect)] = []
        
        // First loop: Fetch the frame ONCE and store it if the point is contained.
        for element in allDescendants {
            guard let frameValue = element.value(forKey: "frame") as? NSValue else { continue }
            let elementFrame = frameValue.cgRectValue
            
            if elementFrame.contains(point) {
                matchingElementsAndFrames.append((element: element, frame: elementFrame))
            }
        }
        
        // Find the smallest element using the stored frames.
        // The `min(by:)` method is a concise way to do this.
        let smallest = matchingElementsAndFrames.min { (first, second) -> Bool in
            let firstArea = first.frame.width * first.frame.height
            let secondArea = second.frame.width * second.frame.height
            return firstArea < secondArea
        }
        
        // The result of `min(by:)` is the entire tuple, so we return its `element` property.
        return smallest?.element
    }
    
    static func tap(_ elementOrCoordinate: NSObject) {
        _ = elementOrCoordinate.perform(NSSelectorFromString("tap"))
    }

    static func longPress(_ elementOrCoordinate: NSObject, duration: TimeInterval) {
        let selector = NSSelectorFromString("pressForDuration:")
        guard elementOrCoordinate.responds(to: selector) else {
            AppLogger.warning("Coordinate does not respond to pressForDuration.")
            return
        }
        typealias PressFn = @convention(c) (AnyObject, Selector, Double) -> Void
        let imp = elementOrCoordinate.method(for: selector)
        let fn = unsafeBitCast(imp, to: PressFn.self)
        fn(elementOrCoordinate, selector, duration)
    }

    static func pressThenDrag(from: NSObject, duration: TimeInterval, to: NSObject) {
        // Use two-argument variant: pressForDuration:thenDragToCoordinate:
        let selector = NSSelectorFromString("pressForDuration:thenDragToCoordinate:")
        guard from.responds(to: selector) else {
            AppLogger.warning("'from' object does not respond to pressForDuration:thenDragToCoordinate:")
            return
        }
        let screenPointSel = NSSelectorFromString("screenPoint")
        if !to.responds(to: screenPointSel) {
            AppLogger.warning("'to' argument is not an XCUICoordinate (missing screenPoint); toClass=\(NSStringFromClass(type(of: to)))")
            return
        }
        typealias PressDragFn = @convention(c) (AnyObject, Selector, Double, AnyObject) -> Void
        let imp = from.method(for: selector)
        let fn = unsafeBitCast(imp, to: PressDragFn.self)
        fn(from, selector, duration, to)
    }
    
    static func pinch(_ element: NSObject, scale: CGFloat, velocity: CGFloat) {
        let selector = NSSelectorFromString("pinchWithScale:velocity:")
        guard element.responds(to: selector) else {
            AppLogger.warning("Element does not respond to pinchWithScale:velocity:")
            return
        }
        typealias PinchFn = @convention(c) (AnyObject, Selector, CGFloat, CGFloat) -> Void
        let imp = element.method(for: selector)
        let fn = unsafeBitCast(imp, to: PinchFn.self)
        fn(element, selector, scale, velocity)
    }

    // Private XCTest symbol. Works when XCTest is already loaded in the runner.
    static func currentXCTestCase() -> AnyObject? {
        // dlsym(nil, …) searches all loaded images, so no hardcoded path
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "_XCTCurrentTestCase") else { return nil }
        typealias Fn = @convention(c) () -> Unmanaged<AnyObject>?
        let f = unsafeBitCast(sym, to: Fn.self)
        return f()?.takeUnretainedValue()
    }

    @discardableResult
    static func addMonitor(
        description: String,
        handler: @escaping (AnyObject /* XCUIElement */) -> Bool
    ) -> AnyObject? {
        guard let testCase = currentXCTestCase() else { return nil }

        // Build an Obj-C block: BOOL (^)(id element)
        typealias Block = @convention(block) (AnyObject) -> Bool
        let block: Block = { element in handler(element) }
        let blockObj: AnyObject = unsafeBitCast(block, to: AnyObject.self)

        let sel = NSSelectorFromString("addUIInterruptionMonitorWithDescription:handler:")
        guard testCase.responds(to: sel) else { return nil }

        typealias IMPType = @convention(c) (AnyObject, Selector, NSString, AnyObject) -> Unmanaged<AnyObject>?
        let imp = testCase.method(for: sel)
        let fn = unsafeBitCast(imp, to: IMPType.self)

        let token = fn(testCase, sel, description as NSString, blockObj)?.takeUnretainedValue()
        if let t = token { tokens.append(t) }
        return token
    }

    static func removeMonitor(_ token: AnyObject) {
        guard let testCase = currentXCTestCase() else { return }
        let sel = NSSelectorFromString("removeUIInterruptionMonitor:")
        guard testCase.responds(to: sel) else { return }
        typealias IMPType = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let imp = testCase.method(for: sel)
        let fn = unsafeBitCast(imp, to: IMPType.self)
        fn(testCase, sel, token)
        tokens.removeAll { $0 === token }
    }
}

// Minimal Swift shim to trigger Simulator Shake without bridging headers
final class SimulatorServicesSwift {
    static func performShake() {
        typealias NotifyPost = @convention(c) (UnsafePointer<CChar>) -> Int32
        let candidates = ["/usr/lib/system/libnotify.dylib", "/usr/lib/libnotify.dylib"]
        var handle: UnsafeMutableRawPointer? = nil
        for path in candidates {
            handle = dlopen(path, RTLD_NOW)
            if handle != nil { break }
        }
        guard let h = handle else { return }
        defer { dlclose(h) }
        guard let sym = dlsym(h, "notify_post") else { return }
        let fn = unsafeBitCast(sym, to: NotifyPost.self)
        _ = "com.apple.UIKit.SimulatorShake".withCString { fn($0) }
    }
}

enum AppLogger {
    static let logger = Logger()

    static func info(_ message: String) {
        logger.log(level: .info, "\(message)")
    }

    static func warning(_ message: String) {
        logger.log(level: .error, "\(message)")
    }

    static func error(_ message: String) {
        logger.log(level: .fault, "\(message)")
    }
}

class ControlWebServer {

    enum Action {
        enum Direction: String {
            case up
            case down
            case left
            case right
        }
        case shutdown
        case switchTo(bundleId: String, launchArguments: [String]?, launchEnvironment: [String: String]?)
        case tap(x: Int, y: Int, longPress: Bool)
        case zoom(x: Int, y: Int, scale: Double, velocity: Double)
        case creep(x: Int, y: Int, direction: Direction, amount: Int)
        case input(string: String)
        case snapshot
        case hierarchy
        case clearInputField
        case hasKeyboard
        case screenInfo
        case openUrl(url: URL)
        case shake
    }

    enum Response {
        case ok
        case badRequest
        case image(Data)
        case text(String)
    }
    
    struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    let port: UInt16
    let screenshotPort: UInt16

    init() {
        // Get ports from environment variables or use defaults
        port = Self.getPortFromEnvironment(name: "CONTROL_SERVER_PORT", defaultValue: 9847)
        screenshotPort = Self.getPortFromEnvironment(name: "SCREENSHOT_SERVER_PORT", defaultValue: 9848)
    }

    private static func getPortFromEnvironment(name: String, defaultValue: UInt16) -> UInt16 {
        // Check environment variables first
        if let portString = ProcessInfo.processInfo.environment[name],
           let port = UInt16(portString) {
            return port
        }

        // Check process arguments for format "NAME=VALUE"
        let argPrefix = "\(name)="
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix(argPrefix),
               let portString = arg.split(separator: "=").last,
               let port = UInt16(portString) {
                return port
            }
        }

        return defaultValue
    }

    let queue = DispatchQueue(label: "TestWebServerQueue")
    let screenhsotQueue = DispatchQueue(label: "ScreenshotQueue", attributes: .concurrent)
    static let longPressDuration: TimeInterval = 1

    func run(_ process: @escaping (Bool, Action) -> Response) {
        // Start the web server
        let listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receiveRequest(on: connection, accumulatedData: Data(), process: process)
        }

        listener.start(queue: queue)
        AppLogger.info("Server started on port \(port)")

        let screenshotListener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: screenshotPort)!)
        screenshotListener.newConnectionHandler = { [weak self] screenshotConnection in
            guard let self else { return }
            screenshotConnection.start(queue: self.screenhsotQueue)
            autoreleasepool {
                if let imageData = XCTestBridge.screenshotJPEG() {
                    self.send(response: .image(imageData), to: screenshotConnection, using: self.screenhsotQueue, shouldLog: false)
                } else {
                    self.send(response: .badRequest, to: screenshotConnection, using: self.screenhsotQueue, shouldLog: false)
                }
            }
            self.screenhsotQueue.asyncAfter(deadline: .now() + 3.0) { [weak screenshotConnection] in
                screenshotConnection?.cancel()
            }
        }

        screenshotListener.start(queue: screenhsotQueue)
        AppLogger.info("Screenshot server started on port \(screenshotPort)")
    }
    
    private func receiveRequest(
        on connection: NWConnection,
        accumulatedData: Data,
        process: @escaping (Bool, Action) -> Response
    ) {
        // Commands are tiny (<=64 KB) and delivered as single packets, so we read everything eagerly.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                AppLogger.warning("ControlWebServer released before finishing request handling")
                return
            }
            
            if let error {
                AppLogger.error("Connection receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            
            var buffer = accumulatedData
            if let chunk = data, !chunk.isEmpty {
                buffer.append(chunk)
            }
            
            guard buffer.isEmpty == false else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.receiveRequest(on: connection, accumulatedData: buffer, process: process)
                }
                return
            }
            
            guard let request = self.parseHTTPRequest(from: buffer) else {
                if isComplete {
                    AppLogger.error("Bad HTTP request received")
                    self.send(response: .badRequest, to: connection, using: self.queue)
                    connection.cancel()
                } else {
                    self.receiveRequest(on: connection, accumulatedData: buffer, process: process)
                }
                return
            }
            
            AppLogger.info("parsing request: \(request.method) \(request.path)")
            let waitsForCompletion = (request.headers["x-qalti-wait"]?.lowercased() != "false")
            
            if let action = self.action(from: request) {
                self.send(response: process(waitsForCompletion, action), to: connection, using: self.queue)
            } else {
                AppLogger.error("unable to map request to action for path \(request.path)")
                self.send(response: .badRequest, to: connection, using: self.queue)
            }
            
            self.queue.asyncAfter(deadline: .now() + 3.0) { [weak connection] in
                connection?.cancel()
            }
        }
    }
    
    private func parseHTTPRequest(from data: Data) -> HTTPRequest? {
        // HTTP/1.1 section 2.1 requires CRLF for request separators, so we split on "\r\n\r\n".
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else { return nil }
        
        let headerEndIndex = headerRange.upperBound
        guard let headerString = String(data: data.subdata(in: data.startIndex..<headerEndIndex), encoding: .utf8) else {
            AppLogger.error("Failed to decode HTTP header data")
            return nil
        }
        
        let headerLines = headerString.components(separatedBy: "\r\n").filter { $0.isEmpty == false }
        guard let requestLine = headerLines.first else {
            AppLogger.error("Missing HTTP request line")
            return nil
        }
        
        let components = requestLine.split(separator: " ")
        guard components.count >= 2 else {
            AppLogger.error("Invalid HTTP request line: \(requestLine)")
            return nil
        }
        
        let method = components[0].uppercased()
        let path = String(components[1])
        
        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        
        let bodyStartOffset = data.distance(from: data.startIndex, to: headerEndIndex)
        let expectedLength = Int(headers["content-length"] ?? "") ?? 0
        let totalLength = bodyStartOffset + expectedLength
        
        if data.count < totalLength {
            return nil
        }
        
        let bodyStart = data.index(data.startIndex, offsetBy: bodyStartOffset)
        let bodyEnd = data.index(bodyStart, offsetBy: expectedLength)
        let body = data.subdata(in: bodyStart..<bodyEnd)
        
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - Action Parsing and Handling
    
    private func action(from request: HTTPRequest) -> Action? {
        let method = request.method.uppercased()
        let path = normalizedPath(request.path)
        
        switch (method, path) {
        case ("POST", "/tap"):
            return parseTapBody(request.body)
        case ("POST", "/zoom"):
            return parseZoomBody(request.body)
        case ("POST", "/creep"):
            return parseCreepBody(request.body)
        case ("POST", "/input"):
            return parseInputBody(request.body)
        case ("POST", "/open-url"):
            return parseOpenURLBody(request.body)
        case ("POST", "/open-app"):
            return parseOpenAppBody(request.body)
        case ("POST", "/shake"):
            return .shake
        case ("POST", "/clear-input-field"):
            return .clearInputField
        case ("POST", "/snapshot"), ("GET", "/snapshot"):
            return .snapshot
        case ("POST", "/shutdown"), ("GET", "/shutdown"):
            return .shutdown
        case ("GET", "/hierarchy"):
            return .hierarchy
        case ("GET", "/has-keyboard"):
            return .hasKeyboard
        case ("GET", "/screen-info"):
            return .screenInfo
        default:
            AppLogger.error("Unsupported request \(method) \(path)")
            return nil
        }
    }
    
    private func parseTapBody(_ body: Data) -> Action? {
        guard let json = jsonDictionary(from: body),
              let x = intValue(json["x"]),
              let y = intValue(json["y"]),
              let isLongPress = boolValue(json["is_long"]) else {
            AppLogger.warning("Invalid tap payload")
            return nil
        }
        return .tap(x: x, y: y, longPress: isLongPress)
    }
    
    private func parseZoomBody(_ body: Data) -> Action? {
        guard let json = jsonDictionary(from: body),
              let x = intValue(json["x"]),
              let y = intValue(json["y"]),
              let scale = doubleValue(json["scale"]),
              let velocity = doubleValue(json["velocity"]) else {
            AppLogger.warning("Invalid zoom payload")
            return nil
        }
        return .zoom(x: x, y: y, scale: scale, velocity: velocity)
    }
    
    private func parseCreepBody(_ body: Data) -> Action? {
        guard let json = jsonDictionary(from: body),
              let x = intValue(json["x"]),
              let y = intValue(json["y"]),
              let amount = intValue(json["amount"]),
              let directionString = stringValue(json["direction"]),
              let direction = Action.Direction(rawValue: directionString.lowercased()) else {
            AppLogger.warning("Invalid creep payload")
            return nil
        }
        return .creep(x: x, y: y, direction: direction, amount: amount)
    }
    
    private func parseInputBody(_ body: Data) -> Action? {
        guard let json = jsonDictionary(from: body),
              let text = json["text"] as? String else {
            AppLogger.warning("Invalid input payload")
            return nil
        }
        return .input(string: text)
    }
    
    private func parseOpenURLBody(_ body: Data) -> Action? {
        guard let json = jsonDictionary(from: body),
              let raw = stringValue(json["url"]),
              let url = url(from: raw) else {
            AppLogger.warning("Invalid open-url payload")
            return nil
        }
        return .openUrl(url: url)
    }
    
    private func parseOpenAppBody(_ body: Data) -> Action? {
        guard let json = jsonDictionary(from: body) else {
            AppLogger.warning("Invalid open-app payload: not JSON")
            return nil
        }
        let bundleId = stringValue(json["bundle_id"]) ?? stringValue(json["bundleId"])
        guard let bundleId else {
            AppLogger.warning("Invalid open-app payload: missing bundle_id")
            return nil
        }
        let launchArguments = stringArray(json["launch_arguments"])
        let launchEnvironment = stringDictionary(json["launch_environment"])
        return .switchTo(
            bundleId: bundleId,
            launchArguments: launchArguments,
            launchEnvironment: launchEnvironment
        )
    }
    
    private func jsonDictionary(from body: Data) -> [String: Any]? {
        guard body.isEmpty == false else { return [:] }
        do {
            return try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        } catch {
            let snippet = String(data: body.prefix(256), encoding: .utf8) ?? "<binary>"
            AppLogger.warning("Failed to decode JSON body: \(error.localizedDescription). Body snippet: \(snippet)")
            return nil
        }
    }
    
    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }
    
    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            let normalized = string.lowercased()
            if ["true", "1", "yes"].contains(normalized) {
                return true
            }
            if ["false", "0", "no"].contains(normalized) {
                return false
            }
        }
        return nil
    }
    
    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, string.isEmpty == false {
            return string
        }
        return nil
    }
    
    private func stringArray(_ value: Any?) -> [String]? {
        if let array = value as? [String] {
            return array
        }
        if let array = value as? [Any] {
            let strings = array.compactMap { $0 as? String }
            return strings.count == array.count ? strings : nil
        }
        return nil
    }
    
    private func stringDictionary(_ value: Any?) -> [String: String]? {
        if let dict = value as? [String: String] {
            return dict
        }
        if let dict = value as? [String: Any] {
            var result: [String: String] = [:]
            for (key, value) in dict {
                if let string = value as? String {
                    result[key] = string
                }
            }
            return result
        }
        return nil
    }
    
    private func url(from rawValue: String) -> URL? {
        if let direct = URL(string: rawValue) {
            return direct
        }
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.insert(charactersIn: ":/?#[]@!$&'()*+,;=%")
        if let encoded = rawValue.addingPercentEncoding(withAllowedCharacters: allowed) {
            return URL(string: encoded)
        }
        return nil
    }
    
    private func normalizedPath(_ rawPath: String) -> String {
        guard rawPath.isEmpty == false else { return rawPath }
        let components = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let basePath = components.first ?? Substring(rawPath)
        if basePath.count > 1, basePath.hasSuffix("/") {
            return String(basePath.dropLast())
        }
        return String(basePath)
    }
    // MARK: - Response Helpers

    func send(response: Response, to connection: NWConnection, using queue: DispatchQueue, shouldLog: Bool = true) {
        let header: String
        var extraBody: Data? = nil
        var statusCode: Int = 0
        var reason: String = ""

        switch response {
        case .ok:
            statusCode = 200
            reason = "OK"
            header = """
            HTTP/1.1 200 OK
            Content-Type: text/plain
            Content-Length: 2
            
            OK
            """
        case .badRequest:
            statusCode = 400
            reason = "Bad Request"
            let errorMessage = NSObject.lastKnownError ?? "Unknown Error"
            let jsonObject: [String: Any] = ["error": errorMessage]
            let data = (try? JSONSerialization.data(withJSONObject: jsonObject, options: [])) ?? Data("{\"error\":\"Bad Input\"}".utf8)
            extraBody = data
            header = """
            HTTP/1.1 400 Bad Request
            Content-Type: application/json; charset=UTF-8
            Content-Length: \(data.count)
            
            
            """
        case .image(let data):
            statusCode = 200
            reason = "OK"
            header = """
            HTTP/1.1 200 OK
            Content-Type: image/jpeg
            Content-Length: \(data.count)
            
            
            """
        case .text(let text):
            if let data = text.data(using: .utf8) {
                statusCode = 200
                reason = "OK"
                header = """
                HTTP/1.1 200 OK
                Content-Type: text/plain; charset=UTF-8
                Content-Length: \(data.count)
                
                
                """
            } else {
                statusCode = 500
                reason = "Internal Server Error"
                header = """
                HTTP/1.1 500 Internal Server Error
                Content-Type: text/plain
                Content-Length: 0
                """
            }

        }

        if shouldLog {
            AppLogger.info("Responding status=\(statusCode) reason=\(reason) error=\(NSObject.lastKnownError ?? "nil")")
        }

        var responseData = header.data(using: .utf8)!
        if case let .image(data) = response {
            responseData.append(data)
        }
        if case let .text(text) = response, let textData = text.data(using: .utf8) {
            responseData.append(textData)
        }
        if let extra = extraBody {
            responseData.append(extra)
        }
        connection.send(content: responseData, contentContext: .finalMessage, completion: .contentProcessed { _ in })
    }
}

extension NSObject {

    static var disableWaitForQuiescence: Bool = false
    static var disableTestFailure: Bool = false

    static var lastKnownError: String? = ""

    private static func swizzle(className: String, originalSelector: Selector, swizzledSelector: Selector) {
        guard let cls = NSClassFromString(className) as? NSObject.Type else { return }

        guard let originalMethod = class_getInstanceMethod(cls, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSObject.self, swizzledSelector)
        else {
            return
        }

        let didAddMethod = class_addMethod(cls, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))

        if didAddMethod {
            class_replaceMethod(cls, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    private static func swizzleClassMethod(className: String, originalSelector: Selector, swizzledSelector: Selector) {
        guard let cls = NSClassFromString(className) else { return }
        guard let metaClass = object_getClass(cls) else { return }

        guard let originalMethod = class_getClassMethod(cls, originalSelector),
              let swizzledMethod = class_getClassMethod(NSObject.self, swizzledSelector)
        else {
            return
        }

        let didAddMethod = class_addMethod(metaClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))

        if didAddMethod {
            class_replaceMethod(metaClass, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    static let swizzleXCUIApplicationProcess: Void = {
        swizzle(
            className: "XCUIApplicationProcess",
            originalSelector: Selector(("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:")),
            swizzledSelector: #selector(nsobj_swizzledWaitForQuiescenceIncludingAnimationsIdle(_:isPreEvent:))
        )
    }()

    static let swizzleXCTIssueShouldInterruptTest: Void = {
        swizzle(
            className: "XCTIssue",
            originalSelector: Selector(("setShouldInterruptTest:")),
            swizzledSelector: #selector(nsobj_swizzledSetShouldInterruptTest(_:))
        )
    }()

    static let swizzleXCTestReporting: Void = {
        swizzleClassMethod(
            className: "XCTContext",
            originalSelector: Selector(("shouldReportActivityWithType:inTestMode:")),
            swizzledSelector: #selector(nsobj_swizzled_shouldReportActivityWithType(_:inTestMode:))
        )

        swizzleClassMethod(
            className: "XCTContext",
            originalSelector: Selector(("_shouldReportActivityWithType:")),
            swizzledSelector: #selector(nsobj_swizzled__shouldReportActivityWithType(_:))
        )
    }()

    @objc func nsobj_swizzledWaitForQuiescenceIncludingAnimationsIdle(_ arg1: Bool, isPreEvent arg2: Bool) {
        if Self.disableWaitForQuiescence {
            return
        }
        self.nsobj_swizzledWaitForQuiescenceIncludingAnimationsIdle(arg1, isPreEvent: arg2)
    }

    @objc func nsobj_swizzledSetShouldInterruptTest(_ arg1: Bool) {
        if Self.disableTestFailure {
            Self.lastKnownError = self.debugDescription
            return
        }
        self.nsobj_swizzledSetShouldInterruptTest(arg1)
    }

    @objc func nsobj_swizzled_testCase_willStartActivity(_ arg1: NSObject, _ arg2: Double) {
    }

    @objc func nsobj_swizzled_testCase_didFinishActivity(_ arg1: NSObject, _ arg2: Double) {
    }

    @objc class func nsobj_swizzled_shouldReportActivityWithType(_ arg1: NSObject, inTestMode arg2: Int64) -> Bool {
        return false
    }

    @objc class func nsobj_swizzled__shouldReportActivityWithType(_ arg1: NSObject) -> Bool {
        return false
    }
}

public final class QaltiRunner {

    static let defaultTimeout: TimeInterval = 3.0
    static let briefTimeout: TimeInterval = 0.1
    // Specific timeouts for the open-app action
    static let openAppNoWaitTimeout: TimeInterval = 3.0
    static let openAppWaitTimeout: TimeInterval = 10.0

    public init() {}

    public func testRunController() throws {
        let server = ControlWebServer()

        NSObject.swizzleXCUIApplicationProcess
        NSObject.swizzleXCTIssueShouldInterruptTest
        NSObject.swizzleXCTestReporting

        NSObject.disableTestFailure = true

        guard let mainScreen = XCTestBridge.application(bundleIdentifier: "com.apple.springboard") else {
            AppLogger.error("Failed to obtain SpringBoard application")
            return
        }
        XCTestBridge.activate(mainScreen)
        var currentAction: ControlWebServer.Action? = nil
        var waitsForCompletion: Bool = true
        var response: ControlWebServer.Response? = nil
        var shuttingDown: Bool = false
        let semaphor: DispatchSemaphore = DispatchSemaphore(value: 0)

        XCTestBridge.setApplicationStateTimeout(Self.defaultTimeout)

        // Swallow everything → XCTest's implicit handler won't auto-tap
        XCTestBridge.addMonitor(description: "Framework no-op") { _ in
            return true
        }

        server.run { requestWaitsForCompletion, action in
            waitsForCompletion = requestWaitsForCompletion
            currentAction = action
            semaphor.wait()
            return response ?? .badRequest
        }

        while shuttingDown == false {
            autoreleasepool {
                if let action = currentAction {
                    AppLogger.info("Running action \(action)")

                    NSObject.lastKnownError = nil

                    if !waitsForCompletion {
                        XCTestBridge.setApplicationStateTimeout(Self.briefTimeout)
                        NSObject.disableWaitForQuiescence = true
                    }

                    switch action {
                    case .openUrl(let url):
                        XCTestBridge.openURL(url)
                        response = .ok
                    case .switchTo(bundleId: let bundleID, launchArguments: let launchArguments, launchEnvironment: let launchEnvironment):
                        // Sometimes app launch timeouts under debug launch, so we need to bump the timeout.
                        if waitsForCompletion {
                            XCTestBridge.setApplicationStateTimeout(Self.openAppWaitTimeout)
                        } else {
                            XCTestBridge.setApplicationStateTimeout(Self.openAppNoWaitTimeout)
                        }
                        if let openApp = XCTestBridge.application(bundleIdentifier: bundleID) {
                            if bundleID == "com.apple.springboard" {
                                XCTestBridge.activate(openApp)
                            } else {
                                XCTestBridge.launch(openApp, launchArguments: launchArguments, launchEnvironment: launchEnvironment)
                            }
                        }
                        // Restore default timeout
                        XCTestBridge.setApplicationStateTimeout(Self.defaultTimeout)
                        if NSObject.lastKnownError != nil {
                            response = .badRequest
                        } else {
                            response = .ok
                        }
                    case .tap(x: let x, y: let y, longPress: let longPress):
                        // Match original semantics: act relative to SpringBoard when it is foreground
                        let candidate = XCTestBridge.focusedOrActiveApp() ?? mainScreen
                        guard XCTestBridge.isRunningForeground(candidate) else {
                            response = .badRequest
                            currentAction = nil
                            semaphor.signal()
                            return
                        }
                        let scale = UIScreen.main.scale
                        let normalizedX = CGFloat(x) / scale
                        let normalizedY = CGFloat(y) / scale

                        if let root = XCTestBridge.rootCoordinate(of: candidate) {
                            if let coord = XCTestBridge.coordinate(root, withOffset: CGVector(dx: normalizedX, dy: normalizedY)) {
                                if longPress {
                                    XCTestBridge.longPress(coord, duration: ControlWebServer.longPressDuration)
                                } else {
                                    XCTestBridge.tap(coord)
                                }
                            } else {
                                AppLogger.warning("Failed to resolve target coordinate for tap")
                            }
                        } else {
                            AppLogger.warning("Failed to obtain root coordinate from base element for tap")
                        }

                        if NSObject.lastKnownError != nil {
                            response = .badRequest
                        } else {
                            response = .ok
                        }
                    case .zoom(x: let x, y: let y, scale: let scale, velocity: let velocity):
                        let candidate = XCTestBridge.focusedOrActiveApp() ?? mainScreen
                        guard XCTestBridge.isRunningForeground(candidate) else {
                            response = .badRequest
                            currentAction = nil
                            semaphor.signal()
                            return
                        }
                        let uiScale = UIScreen.main.scale
                        let normalizedX = CGFloat(x) / uiScale
                        let normalizedY = CGFloat(y) / uiScale
                        let targetPoint = CGPoint(x: normalizedX, y: normalizedY)
                        
                        let elementToPinch = XCTestBridge.findSmallestElementAtPoint(in: candidate, point: targetPoint) ?? candidate
                        
                        if elementToPinch === candidate {
                            AppLogger.warning("Could not resolve specific element for pinch at (\(x), \(y)). Pinching main app view as a fallback.")
                        } else {
                            AppLogger.info("Resolved pinch target to element: \(elementToPinch.debugDescription)")
                        }
                        // XCTest requires velocity to be directional: negative for zoom-out, positive for zoom-in.
                        // Enforce this rule here to make the agent's job easier (to avoid NSInvalidArgumentException).
                        var correctedVelocity = velocity
                        if scale < 1.0 {
                            // Zooming out requires a negative velocity.
                            correctedVelocity = -abs(velocity)
                        } else {
                            // Zooming in requires a positive velocity.
                            correctedVelocity = abs(velocity)
                        }
                        XCTestBridge.pinch(elementToPinch, scale: CGFloat(scale), velocity: CGFloat(correctedVelocity))
                        if NSObject.lastKnownError != nil {
                            response = .badRequest
                        } else {
                            response = .ok
                        }
                    case .clearInputField:
                        let candidate = XCTestBridge.focusedOrActiveApp() ?? mainScreen
                        guard XCTestBridge.isRunningForeground(candidate) else {
                            response = .badRequest
                            currentAction = nil
                            semaphor.signal()
                            return
                        }
                        if let field = XCTestBridge.findActiveTextField(in: candidate) {
                            XCTestBridge.clearText(field)
                        }
                        if NSObject.lastKnownError != nil {
                            response = .badRequest
                        } else {
                            response = .ok
                        }
                    case .hasKeyboard:
                        let candidate = XCTestBridge.focusedOrActiveApp() ?? mainScreen
                        guard XCTestBridge.isRunningForeground(candidate) else {
                            response = .badRequest
                            currentAction = nil
                            semaphor.signal()
                            return
                        }
                        if XCTestBridge.keyboardsCount(candidate) > 0 {
                            response = .text("{\"has_keyboard\": true}")
                        } else {
                            response = .text("{\"has_keyboard\": false}")
                        }
                    case .input(let string):
                        let candidate = XCTestBridge.focusedOrActiveApp() ?? mainScreen
                        guard XCTestBridge.isRunningForeground(candidate) else {
                            response = .badRequest
                            currentAction = nil
                            semaphor.signal()
                            return
                        }

                        if let field = XCTestBridge.findActiveTextField(in: candidate) {
                            XCTestBridge.typeText(field, text: string)
                        } else if let field = XCTestBridge.findActiveTextField(in: mainScreen) {
                            XCTestBridge.typeText(field, text: string)
                        }
                        if NSObject.lastKnownError != nil {
                            response = .badRequest
                        } else {
                            response = .ok
                        }
                    case .creep(x: let x, y: let y, direction: let direction, amount: let amount):
                        guard XCTestBridge.isRunningForeground(mainScreen) else {
                            AppLogger.warning("Creep ignored: main screen not in foreground")
                            response = .badRequest
                            currentAction = nil
                            semaphor.signal()
                            return
                        }

                        let scale = UIScreen.main.scale
                        let origin = CGVector(dx: CGFloat(x) / scale, dy: CGFloat(y) / scale)
                        let offset: CGVector

                        switch direction {
                        case .up:
                            offset = CGVector(dx: 0, dy: -CGFloat(amount) / scale)
                        case .down:
                            offset = CGVector(dx: 0, dy: CGFloat(amount) / scale)
                        case .left:
                            offset = CGVector(dx: -CGFloat(amount) / scale, dy: 0)
                        case .right:
                            offset = CGVector(dx: CGFloat(amount) / scale, dy: 0)
                        }

                        if let root = XCTestBridge.rootCoordinate(of: mainScreen),
                           let element = XCTestBridge.coordinate(root, withOffset: origin),
                           let end = XCTestBridge.coordinate(element, withOffset: offset) {
                            XCTestBridge.pressThenDrag(from: element, duration: 0.05, to: end)
                        } else {
                            if XCTestBridge.rootCoordinate(of: mainScreen) == nil {
                                AppLogger.warning("Failed to obtain root coordinate for swipe")
                            } else if let root = XCTestBridge.rootCoordinate(of: mainScreen), XCTestBridge.coordinate(root, withOffset: origin) == nil {
                                AppLogger.warning("Failed to resolve start coordinate for swipe at origin=(\(origin.dx),\(origin.dy))")
                            } else {
                                AppLogger.warning("Failed to resolve end coordinate for swipe with offset=(\(offset.dx),\(offset.dy))")
                            }
                        }
                        if NSObject.lastKnownError != nil {
                            response = .badRequest
                        } else {
                            response = .ok
                        }
                    case .hierarchy:
                        let appForHierarchy = XCTestBridge.focusedOrActiveApp() ?? mainScreen
                        response = .text(appForHierarchy.debugDescription)
                    case .screenInfo:
                        let scale = UIScreen.main.scale
                        let bounds = UIScreen.main.bounds
                        // Report scale and logical size (points). Pixels can be inferred if needed via snapshot width/height
                        let json = "{" +
                                   "\"scale\": \(scale)," +
                                   "\"points_width\": \(Int(bounds.width))," +
                                   "\"points_height\": \(Int(bounds.height))" +
                                   "}"
                        response = .text(json)
                    case .shake:
                        SimulatorServicesSwift.performShake()
                        response = .ok
                    case .snapshot:
                        if let screenshotData = XCTestBridge.screenshotJPEG(highQuality: true) {
                            response = .image(screenshotData)
                        } else {
                            response = .badRequest
                        }
                    case .shutdown:
                        shuttingDown = true
                        response = .ok
                    }

                    if !waitsForCompletion {
                        XCTestBridge.setApplicationStateTimeout(Self.defaultTimeout)
                        NSObject.disableWaitForQuiescence = false
                    }

                    if let error = NSObject.lastKnownError {
                        AppLogger.error("Last Error: \(error)")
                    }

                    currentAction = nil
                    semaphor.signal()
                } else {
                    usleep(30_000)
                }
            }
        }
    }

}
