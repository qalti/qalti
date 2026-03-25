//
//  XCTestRunGenerator.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 23.06.2025.
//

import Foundation

// - NOTE -
// This class was made as follows:
// I built tests using a special command xcodebuild build-for-testing,
// which in addition to building applications, produced a QaltiRunner.xctestrun file (file format - plist),
// which contained inconvenient relative paths to applications that needed to be launched.
//
// Without thinking twice, I asked chatgpt to carefully look at the contents and write a generator of such files
// according to the original description, where all relative paths would be replaced with absolute ones)
//
// Most of the fields were taken as-is from the generated file, and were not touched,
// since the system worked the first time (the exception is the timeout for running the test)

struct XCTestRunGenerator {
    
    struct Configuration {
        let testBundlePath: String
        let testHostPath: String
        let targetAppPath: String
        let testRootPath: String
        let defaultTestExecutionTimeAllowance: Int
        let testBundleIdentifier: String
        let testHostBundleIdentifier: String
        let targetAppBundleIdentifier: String
        let schemeName: String
        let containerName: String
        let productModuleName: String
        let blueprintName: String
        let blueprintProviderName: String
        let blueprintProviderRelativePath: String
        let additionalEnvironmentVariables: [String: String]
        let additionalCommandLineArguments: [String]
        
        init(
            testBundlePath: String,
            testHostPath: String,
            targetAppPath: String,
            defaultTestExecutionTimeAllowance: Int,
            testRootPath: String = "",
            testBundleIdentifier: String = "com.aiqa.QaltiUITests",
            testHostBundleIdentifier: String = "com.aiqa.QaltiUITests.xctrunner",
            targetAppBundleIdentifier: String = "com.aiqa.QaltiRunner",
            schemeName: String = "QaltiRunner",
            containerName: String = "Qalti",
            productModuleName: String = "QaltiUITests",
            blueprintName: String = "QaltiUITests",
            blueprintProviderName: String = "Qalti",
            blueprintProviderRelativePath: String = "Qalti.xcodeproj",
            additionalEnvironmentVariables: [String: String] = [:],
            additionalCommandLineArguments: [String] = []
        ) {
            self.testBundlePath = testBundlePath
            self.testHostPath = testHostPath
            self.targetAppPath = targetAppPath
            self.testRootPath = testRootPath
            self.defaultTestExecutionTimeAllowance = defaultTestExecutionTimeAllowance
            self.testBundleIdentifier = testBundleIdentifier
            self.testHostBundleIdentifier = testHostBundleIdentifier
            self.targetAppBundleIdentifier = targetAppBundleIdentifier
            self.schemeName = schemeName
            self.containerName = containerName
            self.productModuleName = productModuleName
            self.blueprintName = blueprintName
            self.blueprintProviderName = blueprintProviderName
            self.blueprintProviderRelativePath = blueprintProviderRelativePath
            self.additionalEnvironmentVariables = additionalEnvironmentVariables
            self.additionalCommandLineArguments = additionalCommandLineArguments
        }
    }
    
    private struct XCTestRunPlist: Codable {
        let testConfiguration: TestConfiguration
        let metadata: XCTestRunMetadata
        
        private enum CodingKeys: String, CodingKey {
            case testConfiguration = "QaltiUITests"
            case metadata = "__xctestrun_metadata__"
        }
        
        init(testConfiguration: TestConfiguration, metadata: XCTestRunMetadata) {
            self.testConfiguration = testConfiguration
            self.metadata = metadata
        }
    }
    
    private struct TestConfiguration: Codable {
        let blueprintName: String
        let blueprintProviderName: String
        let blueprintProviderRelativePath: String
        let bundleIdentifiersForCrashReportEmphasis: [String]
        let commandLineArguments: [String]
        let defaultTestExecutionTimeAllowance: Int
        let dependentProductPaths: [String]
        let diagnosticCollectionPolicy: Int
        let environmentVariables: [String: String]
        let isUITestBundle: Bool
        let isXCTRunnerHostedTestBundle: Bool
        let preferredScreenCaptureFormat: String
        let productModuleName: String
        let runOrder: Int
        let systemAttachmentLifetime: String
        let testBundlePath: String
        let testHostBundleIdentifier: String
        let testHostPath: String
        let testRoot: String
        let testLanguage: String
        let testRegion: String
        let testTimeoutsEnabled: Bool
        let testingEnvironmentVariables: [String: String]
        let toolchainsSettingValue: [String]
        let uiTargetAppCommandLineArguments: [String]
        let uiTargetAppEnvironmentVariables: [String: String]
        let uiTargetAppPath: String
        let uiTargetAppPerformanceAntipatternCheckerEnabled: Bool
        let userAttachmentLifetime: String
        let testTargetBundlePath: String
        let xctTargetApplicationPath: String
        let xctRunnerHostPath: String
        
        private enum CodingKeys: String, CodingKey {
            case blueprintName = "BlueprintName"
            case blueprintProviderName = "BlueprintProviderName"
            case blueprintProviderRelativePath = "BlueprintProviderRelativePath"
            case bundleIdentifiersForCrashReportEmphasis = "BundleIdentifiersForCrashReportEmphasis"
            case commandLineArguments = "CommandLineArguments"
            case defaultTestExecutionTimeAllowance = "DefaultTestExecutionTimeAllowance"
            case dependentProductPaths = "DependentProductPaths"
            case diagnosticCollectionPolicy = "DiagnosticCollectionPolicy"
            case environmentVariables = "EnvironmentVariables"
            case isUITestBundle = "IsUITestBundle"
            case isXCTRunnerHostedTestBundle = "IsXCTRunnerHostedTestBundle"
            case preferredScreenCaptureFormat = "PreferredScreenCaptureFormat"
            case productModuleName = "ProductModuleName"
            case runOrder = "RunOrder"
            case systemAttachmentLifetime = "SystemAttachmentLifetime"
            case testBundlePath = "TestBundlePath"
            case testHostBundleIdentifier = "TestHostBundleIdentifier"
            case testHostPath = "TestHostPath"
            case testRoot = "TestRoot"
            case testLanguage = "TestLanguage"
            case testRegion = "TestRegion"
            case testTimeoutsEnabled = "TestTimeoutsEnabled"
            case testingEnvironmentVariables = "TestingEnvironmentVariables"
            case toolchainsSettingValue = "ToolchainsSettingValue"
            case uiTargetAppCommandLineArguments = "UITargetAppCommandLineArguments"
            case uiTargetAppEnvironmentVariables = "UITargetAppEnvironmentVariables"
            case uiTargetAppPath = "UITargetAppPath"
            case uiTargetAppPerformanceAntipatternCheckerEnabled = "UITargetAppPerformanceAntipatternCheckerEnabled"
            case userAttachmentLifetime = "UserAttachmentLifetime"
            case testTargetBundlePath = "TestTargetBundlePath"
            case xctTargetApplicationPath = "_XCTTargetApplicationPath"
            case xctRunnerHostPath = "_XCTRunnerHostPath"
        }
    }
    
    private struct XCTestRunMetadata: Codable {
        let containerInfo: ContainerInfo
        let formatVersion: Int
        
        private enum CodingKeys: String, CodingKey {
            case containerInfo = "ContainerInfo"
            case formatVersion = "FormatVersion"
        }
        
        struct ContainerInfo: Codable {
            let containerName: String
            let schemeName: String
            
            private enum CodingKeys: String, CodingKey {
                case containerName = "ContainerName"
                case schemeName = "SchemeName"
            }
        }
    }
    
    static func generatePlistData(with config: Configuration) throws -> Data {
        var environmentVariables: [String: String] = [
            "APP_DISTRIBUTOR_ID_OVERRIDE": "com.apple.AppStore",
            "OS_ACTIVITY_DT_MODE": "YES",
            "PERFC_ENABLE_EXTENDED_DIAGNOSTIC_FORMAT": "1",
            "PERFC_ENABLE_PROFILE_MODE": "1",
            "PERFC_RESET_INSERT_LIBRARIES": "1",
            "PERFC_SUPPRESS_SYSTEM_REPORTS": "1",
            "SQLITE_ENABLE_THREAD_ASSERTIONS": "1",
            "TERM": "dumb"
        ]
        for (key, value) in config.additionalEnvironmentVariables {
            environmentVariables[key] = value
        }

        let testConfiguration = TestConfiguration(
            blueprintName: config.blueprintName,
            blueprintProviderName: config.blueprintProviderName,
            blueprintProviderRelativePath: config.blueprintProviderRelativePath,
            bundleIdentifiersForCrashReportEmphasis: [
                config.targetAppBundleIdentifier,
                config.testBundleIdentifier
            ],
            commandLineArguments: config.additionalCommandLineArguments,
            defaultTestExecutionTimeAllowance: config.defaultTestExecutionTimeAllowance,
            dependentProductPaths: [
                config.targetAppPath,
                config.testHostPath,
                config.testBundlePath
            ],
            diagnosticCollectionPolicy: 1,
            environmentVariables: environmentVariables,
            isUITestBundle: true,
            isXCTRunnerHostedTestBundle: true,
            preferredScreenCaptureFormat: "screenRecording",
            productModuleName: config.productModuleName,
            runOrder: 0,
            systemAttachmentLifetime: "deleteOnSuccess",
            testBundlePath: config.testBundlePath,
            testHostBundleIdentifier: config.testHostBundleIdentifier,
            testHostPath: config.testHostPath,
            testRoot: config.testRootPath,
            testLanguage: "",
            testRegion: "",
            testTimeoutsEnabled: false,
            testingEnvironmentVariables: [
                "DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug-iphoneos:__TESTROOT__/Debug-iphoneos/PackageFrameworks:__SHAREDFRAMEWORKS__:__PLATFORMS__/MacOSX.platform/Developer/Library/Frameworks",
                "DYLD_LIBRARY_PATH": "__TESTROOT__/Debug-iphoneos:__PLATFORMS__/MacOSX.platform/Developer/usr/lib",
                "PERFC_SUPPRESS_SYSTEM_REPORTS": "1",
                "XCODE_SCHEME_NAME": config.schemeName,
                "__XCODE_BUILT_PRODUCTS_DIR_PATHS": "__TESTROOT__/Debug-iphoneos",
                "__XPC_DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug-iphoneos",
                "__XPC_DYLD_LIBRARY_PATH": "__TESTROOT__/Debug-iphoneos"
            ],
            toolchainsSettingValue: [],
            uiTargetAppCommandLineArguments: [],
            uiTargetAppEnvironmentVariables: [
                "APP_DISTRIBUTOR_ID_OVERRIDE": "com.apple.AppStore",
                "DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug-iphoneos:__TESTROOT__/Debug-iphoneos/PackageFrameworks",
                "DYLD_LIBRARY_PATH": "__TESTROOT__/Debug-iphoneos",
                "XCODE_SCHEME_NAME": config.schemeName,
                "__XCODE_BUILT_PRODUCTS_DIR_PATHS": "__TESTROOT__/Debug-iphoneos",
                "__XPC_DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug-iphoneos",
                "__XPC_DYLD_LIBRARY_PATH": "__TESTROOT__/Debug-iphoneos"
            ],
            uiTargetAppPath: config.targetAppPath,
            uiTargetAppPerformanceAntipatternCheckerEnabled: true,
            userAttachmentLifetime: "deleteOnSuccess",
            testTargetBundlePath: config.testBundlePath,
            xctTargetApplicationPath: config.targetAppPath,
            xctRunnerHostPath: config.testHostPath
        )
        
        let metadata = XCTestRunMetadata(
            containerInfo: XCTestRunMetadata.ContainerInfo(
                containerName: config.containerName,
                schemeName: config.schemeName
            ),
            formatVersion: 1
        )
        
        let plist = XCTestRunPlist(testConfiguration: testConfiguration, metadata: metadata)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        
        return try encoder.encode(plist)
    }
    
    static func generatePlistString(with config: Configuration) throws -> String {
        let data = try generatePlistData(with: config)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "XCTestRunGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert plist data to string"])
        }
        return string
    }
    
    static func writePlist(with config: Configuration, to url: URL) throws {
        let data = try generatePlistData(with: config)
        try data.write(to: url)
    }
}
