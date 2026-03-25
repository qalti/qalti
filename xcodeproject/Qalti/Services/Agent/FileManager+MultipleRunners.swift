//
//  FileManager+MultipleRunners.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 19.09.2025.
//

import Foundation

extension FileManager {

    static var temporaryDirectorySuffix: String = ""

    static func temporaryDirectory() -> URL {
        let result = FileManager.default.temporaryDirectory.appending(path: temporaryDirectorySuffix)
        if !FileManager.default.fileExists(atPath: result.path()) {
            do {
                try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
                return result
            } catch {
                return FileManager.default.temporaryDirectory
            }
        }

        return result
    }

}
