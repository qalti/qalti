//
//  RunnerCompiler.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 15.08.2025.
//

import Foundation
import Logging
import XcodeProj
import PathKit

/// Builds a minimal iOS runner app and UI tests bundle that links against `QaltiRunnerLib.framework`,
/// signs them automatically, and starts `xcodebuild test` against the specified destination.
final class RunnerCompiler: Loggable {
    private static let simulatorTestExecutionTimeAllowance = 365 * 24 * 60 * 60

    struct BuildProcess {
        let process: Process
        let pipe: Pipe
    }

    enum CompilerError: Swift.Error, LocalizedError {
        case failedToDetectTeam
        case missingSimulatorArtifacts(description: String)

        var errorDescription: String? {
            switch self {
            case .failedToDetectTeam:
                return "Sign in to Xcode and create an empty iOS App project once so your Development Team initializes, then retry running on a real device."
            case .missingSimulatorArtifacts(let description):
                return description
            }
        }
    }

    static func buildAndRun(
        deviceID: String,
        isRealDevice: Bool,
        controlServerPort: Int = AppConstants.defaultControlPort,
        screenshotServerPort: Int = AppConstants.defaultScreenshotPort,
        cleanDerivedData: Bool = false,
        env: [String: String] = [:]
    ) throws -> BuildProcess {
        if !isRealDevice {
            return try launchPrebuiltSimulatorRunner(
                deviceID: deviceID,
                controlServerPort: controlServerPort,
                screenshotServerPort: screenshotServerPort,
                env: env
            )
        }

        // 1) Prepare shared temp project directory (stable path enables DerivedData reuse)
        // Use NSTemporaryDirectory via FileManager to avoid hard-coding /tmp
        let baseTemp = FileManager.temporaryDirectory()
        let projectRootURL = baseTemp.appendingPathComponent("QaltiRunnerSharedProject", isDirectory: true)
        if FileManager.default.fileExists(atPath: projectRootURL.path) {
            try FileManager.default.removeItem(at: projectRootURL)
        }
        try FileManager.default.createDirectory(at: projectRootURL, withIntermediateDirectories: true)

        // 2) Prepare xcframework: extract from simulatorbinaries tar.bz2 via AppArchive
        let xcframeworkPath = try AppArchive.xcframeworkPath(for: "QaltiRunnerLib")
        let xcframeworkURL = URL(fileURLWithPath: xcframeworkPath)
        let frameworksDirURL = projectRootURL.appendingPathComponent("Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworksDirURL, withIntermediateDirectories: true)
        let localXCFrameworkURL = frameworksDirURL.appendingPathComponent("QaltiRunnerLib.xcframework", isDirectory: true)
        if FileManager.default.fileExists(atPath: localXCFrameworkURL.path) {
            try FileManager.default.removeItem(at: localXCFrameworkURL)
        }
        try FileManager.default.copyItem(at: xcframeworkURL, to: localXCFrameworkURL)

        // 3) Write minimal sources
        let appSourcesDirURL = projectRootURL.appendingPathComponent("QaltiRunner", isDirectory: true)
        try FileManager.default.createDirectory(at: appSourcesDirURL, withIntermediateDirectories: true)
        let appSwiftURL = appSourcesDirURL.appendingPathComponent("QaltiRunnerApp.swift")
        try minimalRunnerAppSource.write(to: appSwiftURL, atomically: true, encoding: .utf8)

        let testsSourcesDirURL = projectRootURL.appendingPathComponent("QaltiUITests", isDirectory: true)
        try FileManager.default.createDirectory(at: testsSourcesDirURL, withIntermediateDirectories: true)
        let testsSwiftURL = testsSourcesDirURL.appendingPathComponent("QaltiUITests.swift")
        try minimalUITestsSource.write(to: testsSwiftURL, atomically: true, encoding: .utf8)

        // 4) Detect team for signing (required for real devices)
        let developmentTeam: String? = isRealDevice ? detectDevelopmentTeam() : nil
        if isRealDevice && (developmentTeam == nil || developmentTeam?.isEmpty == true) {
            throw CompilerError.failedToDetectTeam
        }

        // 5) Generate Xcode project with XcodeProj
        // Prepare scheme arguments to pass ports down to the app/tests via process arguments
        let schemeArguments: [String] = [
            "CONTROL_SERVER_PORT=\(controlServerPort)",
            "SCREENSHOT_SERVER_PORT=\(screenshotServerPort)"
        ]

        let proj = try generateProject(
            at: projectRootURL,
            appSourcesRelativeDir: "QaltiRunner",
            testsSourcesRelativeDir: "QaltiUITests",
            frameworkRelativePath: "Frameworks/QaltiRunnerLib.framework",
            developmentTeam: developmentTeam,
            schemeArguments: schemeArguments
        )

        // 6) Launch xcodebuild test with provisioning flags
        let destination: String = isRealDevice ? "platform=iOS,id=\(deviceID)" : "platform=iOS Simulator,id=\(deviceID)"
        let projectPath = projectRootURL.appendingPathComponent("QaltiRunner.xcodeproj").path

        var args: [String] = [
            "xcodebuild",
            "test",
            "-project", projectPath,
            "-scheme", "QaltiRunner",
            "-destination", destination
        ]

        // Only real devices require provisioning flags; avoid triggering Xcode account lookups on simulator
        if isRealDevice {
            args += ["-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration"]
        }

        // Use a stable DerivedData path under the temp directory to maximize build cache reuse
        let derivedDataURL = baseTemp.appendingPathComponent("QaltiRunnerDerivedData", isDirectory: true)
        if cleanDerivedData, FileManager.default.fileExists(atPath: derivedDataURL.path) {
            try FileManager.default.removeItem(at: derivedDataURL)
        }
        if !FileManager.default.fileExists(atPath: derivedDataURL.path) {
            try FileManager.default.createDirectory(at: derivedDataURL, withIntermediateDirectories: true)
        }
        args += ["-derivedDataPath", derivedDataURL.path]

        if let team = developmentTeam, !team.isEmpty {
            args.append("DEVELOPMENT_TEAM=\(team)")
        }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        // Propagate environment variables to xcodebuild process and ensure ports are set
        var merged = ProcessInfo.processInfo.environment
        merged["CONTROL_SERVER_PORT"] = String(controlServerPort)
        merged["SCREENSHOT_SERVER_PORT"] = String(screenshotServerPort)
        for (k, v) in env { merged[k] = v }
        process.environment = merged

        try process.run()

        // Observe for unexpected exits (actual restart logic lives in RunnerManager)
        process.terminationHandler = { proc in
            let status = Int(proc.terminationStatus)
            logger.warning("xcodebuild process exited with status \(status)")
        }

        _ = proj // keep reference alive until after write (already saved)

        return BuildProcess(process: process, pipe: pipe)
    }

    // MARK: - Private helpers

    private static func launchPrebuiltSimulatorRunner(
        deviceID: String,
        controlServerPort: Int,
        screenshotServerPort: Int,
        env: [String: String]
    ) throws -> BuildProcess {
        let fm = FileManager.default
        let payloadRoot = try AppArchive.simulatorRunnerPayloadPath()
        let workingRoot = try preparePrebuiltRunnerWorkingRoot()
        let productsDir = workingRoot
            .appendingPathComponent("Build/Products/Release-iphonesimulator", isDirectory: true)
        try fm.createDirectory(at: productsDir, withIntermediateDirectories: true)

        let hostAppName = "QaltiUITests-Runner.app"
        let targetAppName = "QaltiRunner.app"

        let hostAppSource = payloadRoot.appendingPathComponent(hostAppName)
        let targetAppSource = payloadRoot.appendingPathComponent(targetAppName)

        let hostAppDestination = productsDir.appendingPathComponent(hostAppName)
        let targetAppDestination = productsDir.appendingPathComponent(targetAppName)

        try copyReplacingItem(from: hostAppSource, to: hostAppDestination, description: hostAppName)
        try copyReplacingItem(from: targetAppSource, to: targetAppDestination, description: targetAppName)

        let testBundleURL = try locateUITestBundle(inRunner: hostAppDestination)
        let generatedXCTestRunURL = workingRoot.appendingPathComponent("Generated.xctestrun")

        try generateSimulatorXCTestRun(
            destinationURL: generatedXCTestRunURL,
            hostAppPath: hostAppDestination.path,
            testBundlePath: testBundleURL.path,
            targetAppPath: targetAppDestination.path,
            productsRootPath: productsDir.path,
            controlServerPort: controlServerPort,
            screenshotServerPort: screenshotServerPort
        )

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "xcodebuild",
            "test-without-building",
            "-xctestrun", generatedXCTestRunURL.path,
            "-destination", "platform=iOS Simulator,id=\(deviceID)"
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        process.currentDirectoryURL = workingRoot

        var merged = ProcessInfo.processInfo.environment
        merged["CONTROL_SERVER_PORT"] = String(controlServerPort)
        merged["SCREENSHOT_SERVER_PORT"] = String(screenshotServerPort)
        for (k, v) in env { merged[k] = v }
        process.environment = merged

        try process.run()
        process.terminationHandler = { proc in
            let status = Int(proc.terminationStatus)
            print("[xcodebuild] process exited with status \(status)")
        }

        return BuildProcess(process: process, pipe: pipe)
    }

    private static func generateProject(
        at rootURL: URL,
        appSourcesRelativeDir: String,
        testsSourcesRelativeDir: String,
        frameworkRelativePath: String,
        developmentTeam: String?,
        schemeArguments: [String]
    ) throws -> XcodeProj {
        let root = Path(rootURL.path)

        // Files
        let appFileRef = PBXFileReference(sourceTree: .group, lastKnownFileType: "sourcecode.swift", path: "QaltiRunnerApp.swift")
        let appGroup = PBXGroup(children: [appFileRef], sourceTree: .group, path: appSourcesRelativeDir)

        let testsFileRef = PBXFileReference(sourceTree: .group, lastKnownFileType: "sourcecode.swift", path: "QaltiUITests.swift")
        let testsGroup = PBXGroup(children: [testsFileRef], sourceTree: .group, path: testsSourcesRelativeDir)

        let frameworksGroup = PBXGroup(children: [], sourceTree: .group, path: "Frameworks")
        let xcframeworkRef = PBXFileReference(sourceTree: .group, explicitFileType: "wrapper.xcframework", path: "QaltiRunnerLib.xcframework")
        frameworksGroup.children.append(xcframeworkRef)

        let productsGroup = PBXGroup(children: [], sourceTree: .group)

        let mainGroup = PBXGroup(children: [appGroup, testsGroup, frameworksGroup, productsGroup], sourceTree: .group)

        // Targets
        let appSourceBuild = PBXBuildFile(file: appFileRef)
        let appSourcesPhase = PBXSourcesBuildPhase(files: [appSourceBuild])
        let appFrameworksPhase = PBXFrameworksBuildPhase()
        let appResourcesPhase = PBXResourcesBuildPhase()
        let appProductRef = PBXFileReference(sourceTree: .buildProductsDir, explicitFileType: "wrapper.application", path: "QaltiRunner.app")
        let appTarget = PBXNativeTarget(
            name: "QaltiRunner",
            buildConfigurationList: nil,
            buildPhases: [appSourcesPhase, appFrameworksPhase, appResourcesPhase],
            buildRules: [],
            dependencies: [],
            productName: "QaltiRunner",
            product: appProductRef,
            productType: .application
        )

        let testsSourceBuild = PBXBuildFile(file: testsFileRef)
        let testsSourcesPhase = PBXSourcesBuildPhase(files: [testsSourceBuild])

        // Link xcframework to both app and tests target
        let testFrameworkBuild = PBXBuildFile(file: xcframeworkRef)
        let appFrameworkBuild = PBXBuildFile(file: xcframeworkRef)
        appFrameworksPhase.files?.append(appFrameworkBuild)
        let testsFrameworksPhase = PBXFrameworksBuildPhase(files: [testFrameworkBuild])

        let embedFrameworks = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks",
            files: []
        )
        let embedBuild = PBXBuildFile(file: xcframeworkRef, settings: ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]])
        embedFrameworks.files?.append(embedBuild)

        let testsProductRef = PBXFileReference(sourceTree: .buildProductsDir, explicitFileType: "wrapper.cfbundle", path: "QaltiUITests.xctest")
        let testsTarget = PBXNativeTarget(
            name: "QaltiUITests",
            buildConfigurationList: nil,
            buildPhases: [testsSourcesPhase, testsFrameworksPhase, embedFrameworks],
            buildRules: [],
            dependencies: [],
            productName: "QaltiUITests",
            product: testsProductRef,
            productType: .uiTestBundle
        )

        // Ensure framework search path for both targets
       // Put products into Products group so they appear in Xcode and are serialized
        productsGroup.children.append(appProductRef)
        productsGroup.children.append(testsProductRef)

        // Link tests to app
        // We'll create proxy after project is created to be able to pass the project as portal
        // Temporarily register dependency object and fill later
        let targetDependency = PBXTargetDependency(name: appTarget.name)
        testsTarget.dependencies.append(targetDependency)

        let frameworkSearchPath = "$(SRCROOT)/Frameworks"

        // Project
        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: buildSettings(isApp: true, developmentTeam: developmentTeam))
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: buildSettings(isApp: true, developmentTeam: developmentTeam))
        for cfg in [debugConfig, releaseConfig] {
            cfg.buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string("$(inherited) \(frameworkSearchPath)")
        }
        let appConfigList = XCConfigurationList(buildConfigurations: [debugConfig, releaseConfig], defaultConfigurationName: "Debug")
        appTarget.buildConfigurationList = appConfigList

        let testsDebug = XCBuildConfiguration(name: "Debug", buildSettings: buildSettings(isApp: false, developmentTeam: developmentTeam))
        let testsRelease = XCBuildConfiguration(name: "Release", buildSettings: buildSettings(isApp: false, developmentTeam: developmentTeam))
        for cfg in [testsDebug, testsRelease] {
            cfg.buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string("$(inherited) \(frameworkSearchPath)")
        }
        let testsConfigList = XCConfigurationList(buildConfigurations: [testsDebug, testsRelease], defaultConfigurationName: "Debug")
        testsTarget.buildConfigurationList = testsConfigList

        let projectDebug = XCBuildConfiguration(name: "Debug", buildSettings: [
            "FRAMEWORK_SEARCH_PATHS": .string("$(inherited) \(frameworkSearchPath)"),
        ])
        let projectRelease = XCBuildConfiguration(name: "Release", buildSettings: [
            "FRAMEWORK_SEARCH_PATHS": .string("$(inherited) \(frameworkSearchPath)"),
        ])
        let projectConfigs = XCConfigurationList(buildConfigurations: [projectDebug, projectRelease], defaultConfigurationName: "Debug")



        let project = PBXProject(
            name: "QaltiRunner",
            buildConfigurationList: projectConfigs,
            compatibilityVersion: "Xcode 14.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            developmentRegion: "en",
            hasScannedForEncodings: 0,
            knownRegions: ["en"],
            productsGroup: productsGroup,
            projectDirPath: "",
            projectRoots: [""],
            targets: [appTarget, testsTarget],
        )

        // Set UI tests association is optional when TEST_TARGET_NAME and dependency are set

        // Now create the proxy and assign into dependency
        let containerProxy = PBXContainerItemProxy(
            containerPortal: .project(project),
            remoteGlobalID: .object(appTarget),
            proxyType: PBXContainerItemProxy.ProxyType.reference,
            remoteInfo: appTarget.name
        )
        targetDependency.targetProxy = containerProxy
        targetDependency.target = appTarget

        let pbxproj = PBXProj(rootObject: project, objectVersion: 56)
        // Register all created objects so they get written to project.pbxproj
        let allObjects: [PBXObject] = [
            project,
            mainGroup, productsGroup, frameworksGroup, appGroup, testsGroup,
            appFileRef, testsFileRef, xcframeworkRef,
            appProductRef, testsProductRef,
            appTarget, testsTarget,
            appSourcesPhase, appFrameworksPhase, appResourcesPhase,
            testsSourcesPhase, testsFrameworksPhase, embedFrameworks,
            appSourceBuild, testsSourceBuild, testFrameworkBuild, embedBuild,
            targetDependency, containerProxy,
            debugConfig, releaseConfig, testsDebug, testsRelease, projectDebug, projectRelease,
            appConfigList, testsConfigList, projectConfigs
        ]
        for obj in allObjects { pbxproj.add(object: obj) }
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)

        // Write project
        let projPath = root + "QaltiRunner.xcodeproj"
        try xcodeproj.write(path: projPath)

        // Write scheme
        try writeSharedScheme(root: root, appTarget: appTarget, testsTarget: testsTarget, schemeArguments: schemeArguments)

        return xcodeproj
    }

    private static func writeSharedScheme(root: Path, appTarget: PBXNativeTarget, testsTarget: PBXNativeTarget, schemeArguments: [String]) throws {
        let schemesDir = root + "QaltiRunner.xcodeproj" + "xcshareddata" + "xcschemes"
        try schemesDir.mkpath()

        let appBuildable = XCScheme.BuildableReference(referencedContainer: "container:QaltiRunner.xcodeproj", blueprintIdentifier: appTarget.uuid, buildableName: "QaltiRunner.app", blueprintName: appTarget.name)
        let testsBuildable = XCScheme.BuildableReference(referencedContainer: "container:QaltiRunner.xcodeproj", blueprintIdentifier: testsTarget.uuid, buildableName: "QaltiUITests.xctest", blueprintName: testsTarget.name)

        let buildEntry = XCScheme.BuildAction.Entry(buildableReference: appBuildable, buildFor: [.running])
        let buildAction = XCScheme.BuildAction(buildActionEntries: [buildEntry])

        let testable = XCScheme.TestableReference(skipped: false, buildableReference: testsBuildable)

        // Prepare command-line arguments so the app/tests receive CONTROL_SERVER_PORT/SCREENSHOT_SERVER_PORT via ProcessInfo.arguments
        let cliArgs = XCScheme.CommandLineArguments(arguments: schemeArguments.map { XCScheme.CommandLineArguments.CommandLineArgument(name: $0, enabled: true) })

        let testAction = XCScheme.TestAction(
            buildConfiguration: "Debug",
            macroExpansion: appBuildable,
            testables: [testable],
            commandlineArguments: cliArgs
        )

        let runnable = XCScheme.BuildableProductRunnable(buildableReference: appBuildable)
        let launchAction = XCScheme.LaunchAction(runnable: runnable, buildConfiguration: "Debug", commandlineArguments: cliArgs)
        let profileAction = XCScheme.ProfileAction(runnable: runnable, buildConfiguration: "Release")
        let analyzeAction = XCScheme.AnalyzeAction(buildConfiguration: "Debug")
        let archiveAction = XCScheme.ArchiveAction(buildConfiguration: "Release", revealArchiveInOrganizer: true)

        let scheme = XCScheme(name: "QaltiRunner", lastUpgradeVersion: nil, version: nil, buildAction: buildAction, testAction: testAction, launchAction: launchAction, profileAction: profileAction, analyzeAction: analyzeAction, archiveAction: archiveAction)

        let schemePath = schemesDir + "QaltiRunner.xcscheme"
        try scheme.write(path: schemePath, override: true)
    }

    private static func buildSettings(isApp: Bool, developmentTeam: String?) -> BuildSettings {
        var settings: BuildSettings = [
            "SWIFT_VERSION": "5.0",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "CODE_SIGN_STYLE": "Automatic",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
            "FRAMEWORK_SEARCH_PATHS": "$(inherited) $(SRCROOT)/Frameworks",
            "SWIFT_INCLUDE_PATHS": .string("$(SRCROOT)/Frameworks/QaltiRunnerLib.framework/Modules"),
            "OTHER_LDFLAGS": .string("$(inherited) -framework QaltiRunnerLib"),
            "SUPPORTED_PLATFORMS": .array(["iphoneos", "iphonesimulator"]),
            "TARGETED_DEVICE_FAMILY": .string("1,2"),
            "GENERATE_INFOPLIST_FILE": .string("YES")
        ]
        let bundlePrefix = developmentTeam ?? "aiqa"
        
        if isApp {
            settings["PRODUCT_NAME"] = .string("QaltiRunner")
            settings["PRODUCT_BUNDLE_IDENTIFIER"] = .string("com.\(bundlePrefix).QaltiRunner")
            settings["INFOPLIST_KEY_UISupportedInterfaceOrientations"] = .array(["UIInterfaceOrientationPortrait"]) // to avoid generic plist warnings
            settings["INFOPLIST_KEY_UISupportedInterfaceOrientations~ipad"] = .array([
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight"
            ])
        } else {
            settings["PRODUCT_NAME"] = .string("QaltiUITests")
            settings["PRODUCT_BUNDLE_IDENTIFIER"] = .string("com.\(bundlePrefix).QaltiUITests")
            settings["WRAPPER_EXTENSION"] = .string("xctest")
        }
        if let team = developmentTeam, !team.isEmpty {
            settings["DEVELOPMENT_TEAM"] = .string(team)
            settings["CODE_SIGN_IDENTITY"] = .string("Apple Development")
            settings["PROVISIONING_PROFILE_SPECIFIER"] = .string("")
        } else {
            settings["CODE_SIGNING_ALLOWED"] = .string("NO")
            settings["CODE_SIGNING_REQUIRED"] = .string("NO")
        }
        return settings
    }

    private static var minimalRunnerAppSource: String {
        return """
        import SwiftUI

        @main
        struct QaltiRunnerApp: App {
            var body: some Scene {
                WindowGroup { Text("Hello from Qalti") }
            }
        }
        """
    }

    private static var minimalUITestsSource: String {
        return """
        import XCTest
        import QaltiRunnerLib

        final class QaltiUITests: XCTestCase {
            let runner = QaltiRunnerLib.QaltiRunner()

            @MainActor
            func testRunController() throws {
                try runner.testRunController()
            }
        }
        """
    }

    private static func detectDevelopmentTeam() -> String? {
        // 1) List code signing identities and pick an active Apple Development identity
        guard let identitiesOutput = runCommand(
            executable: "/usr/bin/security",
            arguments: ["find-identity", "-p", "codesigning", "-v"],
            input: nil
        ) else { return nil }

        for line in identitiesOutput.components(separatedBy: .newlines) {
            guard line.contains("Apple Development") else { continue }
            guard !line.contains("CSSMERR") else { continue } // skip revoked/errored identities

            // Parse SHA-1 hash and derive TEAMID from certificate OU
            guard let hash = parseSHA1Hash(fromIdentityLine: line) else { continue }
            if let teamFromCert = extractTeamIDFromCertificate(hash: hash) {
                return teamFromCert
            }
        }
        return nil
    }

    private static func parseSHA1Hash(fromIdentityLine line: String) -> String? {
        // Example line:
        //  3) 4BAFB1191BA9042449D27937E0ED637A5903FCF9 "Apple Development: Name (TEAMID)"
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let closeParenIndex = trimmed.firstIndex(of: ")") else {
            logger.warning("parseSHA1Hash: failed to find ')' in identity line: \(line)")
            return nil
        }
        let afterParen = trimmed.index(after: closeParenIndex)
        let remainder = trimmed[afterParen...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSpace = remainder.firstIndex(where: { $0.isWhitespace }) else {
            logger.warning("parseSHA1Hash: failed to find hash token in identity line: \(line)")
            return nil
        }
        let hashCandidate = String(remainder[..<firstSpace]).uppercased()
        let validHex = CharacterSet(charactersIn: "0123456789ABCDEF")
        let allHex = hashCandidate.unicodeScalars.allSatisfy { validHex.contains($0) }
        guard hashCandidate.count == 40, allHex else {
            logger.warning("parseSHA1Hash: not a valid 40-char hex hash in identity line: \(line)")
            return nil
        }
        return hashCandidate
    }

    private static func extractTeamIDFromCertificate(hash: String) -> String? {
        // 2) Dump all certificates with hashes and PEM blocks
        guard let certsOutput = runCommand(
            executable: "/usr/bin/security",
            arguments: ["find-certificate", "-Z", "-a", "-p"],
            input: nil
        ) else {
            logger.error("extractTeamIDFromCertificate: failed to run 'security find-certificate' for hash \(hash)")
            return nil
        }

        // 3) Locate the PEM block for the matching SHA-1 hash
        let lines = certsOutput.components(separatedBy: .newlines)
        var isMatchingSection = false
        var isCapturingPEM = false
        var pemLines: [String] = []

        for line in lines {
            if line.contains("SHA-1 hash:") && line.uppercased().contains(hash) {
                isMatchingSection = true
                continue
            }
            if isMatchingSection {
                if line.contains("-----BEGIN CERTIFICATE-----") {
                    isCapturingPEM = true
                }
                if isCapturingPEM {
                    pemLines.append(line)
                    if line.contains("-----END CERTIFICATE-----") {
                        break
                    }
                }
                // If we reached end-of-section without hitting PEM, and saw END CERTIFICATE elsewhere, stop matching
                if line.contains("END CERTIFICATE") && !isCapturingPEM {
                    isMatchingSection = false
                }
            }
        }

        let pem = pemLines.joined(separator: "\n")
        guard pem.contains("BEGIN CERTIFICATE"), pem.contains("END CERTIFICATE") else {
            logger.error("extractTeamIDFromCertificate: failed to capture PEM for hash \(hash)")
            return nil
        }

        // 4) Ask openssl to print subject and extract OU as Team ID
        guard let subjectOutput = runCommand(
            executable: "/usr/bin/openssl",
            arguments: ["x509", "-noout", "-subject", "-nameopt", "RFC2253"],
            input: pem.data(using: .utf8)
        ) else {
            logger.error("extractTeamIDFromCertificate: failed to parse subject via openssl for hash \(hash)")
            return nil
        }

        // Typical subject contains OU=TEAMID
        // Examples (RFC2253): subject= CN=Apple Development: Name (XXXXXXXXXX),OU=XXXXXXXXXX,O=Apple Inc.,C=US
        let upper = subjectOutput.uppercased()
        if let range = upper.range(of: "OU=") {
            let afterOU = upper[range.upperBound...]
            let terminators: CharacterSet = CharacterSet(charactersIn: ",/\n\r")
            let teamId = String(afterOU.prefix { ch in
                guard let scalar = ch.unicodeScalars.first else { return false }
                return !terminators.contains(scalar)
            })
            if teamId.count == 10 { return teamId }
            logger.warning("extractTeamIDFromCertificate: parsed OU but invalid team id '\(teamId)' for hash \(hash)")
        }
        logger.warning("extractTeamIDFromCertificate: OU=TEAMID not found in subject for hash \(hash)")
        return nil
    }

    private static func runCommand(executable: String, arguments: [String], input: Data?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        if let input = input {
            let pipe = Pipe()
            process.standardInput = pipe
            do {
                try process.run()
            } catch {
                return nil
            }
            pipe.fileHandleForWriting.write(input)
            try? pipe.fileHandleForWriting.close()
        } else {
            do {
                try process.run()
            } catch {
                return nil
            }
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    // MARK: - Prebuilt runner helpers

    private static func copyReplacingItem(from source: URL, to destination: URL, description: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw CompilerError.missingSimulatorArtifacts(
                description: "Missing \(description) in the simulator runner archive. Re-run scripts/archive_simulator_runner.sh and rebuild the macOS app."
            )
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private static func locateUITestBundle(inRunner runnerURL: URL) throws -> URL {
        let plugInsURL = runnerURL.appendingPathComponent("PlugIns", isDirectory: true)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: plugInsURL, includingPropertiesForKeys: nil),
              let bundle = contents.first(where: { $0.pathExtension == "xctest" })
        else {
            throw CompilerError.missingSimulatorArtifacts(
                description: "Failed to locate UI test bundle inside \(runnerURL.lastPathComponent). Re-run scripts/archive_simulator_runner.sh."
            )
        }
        return bundle
    }

    private static func generateSimulatorXCTestRun(
        destinationURL: URL,
        hostAppPath: String,
        testBundlePath: String,
        targetAppPath: String,
        productsRootPath: String,
        controlServerPort: Int,
        screenshotServerPort: Int
    ) throws {
        let portEnvironment = [
            "CONTROL_SERVER_PORT": "\(controlServerPort)",
            "SCREENSHOT_SERVER_PORT": "\(screenshotServerPort)"
        ]
        let portArguments = [
            "CONTROL_SERVER_PORT=\(controlServerPort)",
            "SCREENSHOT_SERVER_PORT=\(screenshotServerPort)"
        ]

        let config = XCTestRunGenerator.Configuration(
            testBundlePath: testBundlePath,
            testHostPath: hostAppPath,
            targetAppPath: targetAppPath,
            defaultTestExecutionTimeAllowance: simulatorTestExecutionTimeAllowance,
            testRootPath: productsRootPath,
            additionalEnvironmentVariables: portEnvironment,
            additionalCommandLineArguments: portArguments
        )
        try XCTestRunGenerator.writePlist(with: config, to: destinationURL)
    }

    private static func preparePrebuiltRunnerWorkingRoot() throws -> URL {
        let fm = FileManager.default
        let cacheRoot: URL
        if let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheRoot = cachesURL.appendingPathComponent("Qalti", isDirectory: true)
        } else {
            cacheRoot = FileManager.temporaryDirectory()
        }

        let workingRoot = cacheRoot.appendingPathComponent("PrebuiltSimulatorRunner", isDirectory: true)
        if fm.fileExists(atPath: workingRoot.path) {
            try fm.removeItem(at: workingRoot)
        }
        try fm.createDirectory(at: workingRoot, withIntermediateDirectories: true)
        return workingRoot
    }
}
