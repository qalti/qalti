//
//  MockFileManager.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import XCTest
@testable import Qalti

private class MockDirectoryEnumerator: FileManager.DirectoryEnumerator {
    private let urls: [URL]
    private var currentIndex = 0

    init(urls: [URL]) {
        self.urls = urls
        super.init()
    }

    override func nextObject() -> Any? {
        guard currentIndex < urls.count else {
            return nil
        }
        let url = urls[currentIndex]
        currentIndex += 1
        return url
    }
}

class MockFileManager: FileSystemManaging {

    var temporaryDirectory: URL = URL(fileURLWithPath: "/tmp/qalti-tests")

    // In-memory file system
    var files = [URL: Data]()
    var removedItems: [URL] = []
    var createdDirectories = Set<URL>()
    var enumeratorResults: [URL: [URL]] = [:]

    // Simulated error flags
    var shouldThrowWriteError = false
    var shouldThrowRemoveError = false
    var shouldThrowCreateDirectoryError = false
    var shouldThrowMoveError = false
    var shouldThrowCreateFileError = false

    // MARK: - Read / Write
    func contents(atPath path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        return files[url]
    }

    func write(_ data: Data, to url: URL) throws {
        if shouldThrowWriteError {
            throw NSError(domain: "MockFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated write error"])
        }
        files[url] = data
    }

    // MARK: - Remove
    func removeItem(at URL: URL) throws {
        if shouldThrowRemoveError {
            throw NSError(domain: "MockFileManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Simulated remove error"])
        }
        files.removeValue(forKey: URL)
        removedItems.append(URL)
        createdDirectories.remove(URL)
    }

    // MARK: - Move
    func moveItem(at URL: URL, to newURL: URL) throws {
        if shouldThrowMoveError {
            throw NSError(domain: "MockFileManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Simulated move error"])
        }
        if let data = files.removeValue(forKey: URL) {
            files[newURL] = data
        } else if createdDirectories.contains(URL) {
            createdDirectories.remove(URL)
            createdDirectories.insert(newURL)
        }
    }

    // MARK: - Create
    func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        if shouldThrowCreateFileError {
            return false
        }
        let url = URL(fileURLWithPath: path)
        files[url] = data ?? Data()
        return true
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        if shouldThrowCreateDirectoryError {
            throw NSError(domain: "MockFileManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Simulated create directory error"])
        }
        createdDirectories.insert(url)
    }

    // MARK: - File existence
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let url = URL(fileURLWithPath: path)
        if createdDirectories.contains(url) {
            isDirectory?.pointee = true
            return true
        }
        if files[url] != nil {
            isDirectory?.pointee = false
            return true
        }
        return false
    }

    // MARK: - Enumerator
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions,
        errorHandler handler: ((URL, Error) -> Bool)?
    ) -> FileManager.DirectoryEnumerator? {
        if let urlsToReturn = enumeratorResults[url] {
            return MockDirectoryEnumerator(urls: urlsToReturn)
        }
        return MockDirectoryEnumerator(urls: [])
    }
}
