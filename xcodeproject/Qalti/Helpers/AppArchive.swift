//
//  AppArchive.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 23.06.2025.
//

import Foundation

/// Extracts the .tar.bz2 archive embedded in the bundle and
/// returns the full path to the `.app` bundle inside it.
/// The archive is deleted and re-extracted on first use per launch.
enum AppArchive {
    enum Error: Swift.Error {
        case archiveMissing
        case extractionFailed
        case appNotFound
    }
    
    private static var firstUseTracker: [String: Bool] = [:]

    static func xcframeworkPath(for baseName: String) throws -> String {
        return try path(forArchiveNamed: baseName, expectingSuffix: ".xcframework", archiveExtension: "tar.bz2")
    }

    static func simulatorRunnerPayloadPath() throws -> URL {
        let path = try path(forArchiveNamed: "qalti-runner-simulator", expectingSuffix: nil, archiveExtension: "tar.bz2")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func path(
        forArchiveNamed baseName: String,
        expectingSuffix: String?,
        archiveExtension: String
    ) throws -> String {
        let fm = FileManager.default

        // e.g. …/tmp/Qalti
        let outDir = FileManager.temporaryDirectory().appendingPathComponent(baseName, isDirectory: true)
        
        // Check if this is the first use of this baseName
        let isFirstUse = firstUseTracker[baseName] != true
        if isFirstUse {
            firstUseTracker[baseName] = true
            // Delete existing directory if it exists
            if fm.fileExists(atPath: outDir.path) {
                try fm.removeItem(at: outDir)
            }
        } else {
            // Not first use, check if already extracted
            if fm.fileExists(atPath: outDir.path) {
                if let suffix = expectingSuffix {
                    if let item = try fm.contentsOfDirectory(atPath: outDir.path)
                        .first(where: { $0.hasSuffix(suffix) })
                    {
                        return outDir.appendingPathComponent(item).path
                    }
                } else {
                    return outDir.path
                }
            }
        }

        // 1) Locate the embedded archive
        guard let archiveURL = Bundle.main.url(forResource: baseName,
                                               withExtension: archiveExtension,
                                               subdirectory: "simulatorbinaries")
        else { throw Error.archiveMissing }

        // 2) Ensure temp dir exists & run `/usr/bin/tar -xjf …`
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        let task = Process()
        task.launchPath = "/usr/bin/tar"
        let tarFlag: String
        if archiveExtension.hasSuffix("gz") {
            tarFlag = "-xzf"
        } else {
            tarFlag = "-xjf"
        }
        task.arguments = [tarFlag, archiveURL.path, "-C", outDir.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw Error.extractionFailed }

        // 3) Find the expected item we just extracted
        if let suffix = expectingSuffix {
            guard let item = try fm.contentsOfDirectory(atPath: outDir.path)
                    .first(where: { $0.hasSuffix(suffix) })
            else { throw Error.appNotFound }

            return outDir.appendingPathComponent(item).path
        } else {
            return outDir.path
        }
    }
}
