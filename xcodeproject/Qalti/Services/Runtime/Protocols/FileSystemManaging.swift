//
//  FileSystemManaging.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 28.11.25.
//

import Foundation

/// An abstraction for file system operations to allow for mocking in tests.
protocol FileSystemManaging {
    /// The URL of the directory for temporary files.
    var temporaryDirectory: URL { get }

    /// Reads the contents of a file at a given path.
    func contents(atPath path: String) -> Data?

    /// Writes data to a URL.
    func write(_ data: Data, to url: URL) throws

    /// Removes the item at the specified URL.
    func removeItem(at URL: URL) throws

    /// Moves the item at the specified URL to another location.
    func moveItem(at URL: URL, to newURL: URL) throws

    /// Creates file at the specified URL.
    func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]?) -> Bool

    /// Creates directory at the specified URL.
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws

    /// Checks the existence of file at the specified URL.
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions,
        errorHandler handler: ((URL, Error) -> Bool)?
    ) -> FileManager.DirectoryEnumerator?

}

extension FileManager: FileSystemManaging {    
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }
}
