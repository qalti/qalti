import Foundation

/// Service responsible for exporting default prompts to files
class PromptExporter {
    static let shared = PromptExporter()
    
    private init() {}
    
    /// Export all default prompts to the .qalti/prompts directory
    /// - Returns: Result indicating success or failure with details
    func exportDefaultPrompts() -> ExportResult {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let promptsDir = documentsPath.appendingPathComponent("Qalti/.qalti/prompts")
        
        // Create directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: promptsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return .failure("Failed to create prompts directory: \(error.localizedDescription)")
        }
        
        var exportedFiles: [String] = []
        var failedFiles: [String: String] = [:]
        
        // Export all prompts using centralized collection
        for (fileName, contentProvider) in Prompts.allPrompts {
            let result = writePromptFile(
                directory: promptsDir,
                fileName: fileName,
                content: contentProvider()
            )
            
            switch result {
            case .success:
                exportedFiles.append(fileName)
            case .failure(let error):
                failedFiles[fileName] = error
            }
        }
        
        // Return result
        if failedFiles.isEmpty {
            return .success(
                message: "Successfully exported \(exportedFiles.count) prompt files to:\n\(promptsDir.path)",
                exportedFiles: exportedFiles,
                directoryPath: promptsDir.path
            )
        } else {
            let successCount = exportedFiles.count
            let failureCount = failedFiles.count
            let errorDetails = failedFiles.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            
            return .failure(
                "Exported \(successCount) files successfully, but \(failureCount) failed:\n\(errorDetails)\n\nDirectory: \(promptsDir.path)"
            )
        }
    }
    
    /// Write a single prompt file
    private func writePromptFile(directory: URL, fileName: String, content: String) -> WriteResult {
        let fileURL = directory.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .success
        } catch {
            return .failure("Failed to write file: \(error.localizedDescription)")
        }
    }
    
    /// Check if prompts directory exists and has files
    func getPromptsDirectoryStatus() -> DirectoryStatus {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let promptsDir = documentsPath.appendingPathComponent("Qalti/.qalti/prompts")
        
        guard fileManager.fileExists(atPath: promptsDir.path) else {
            return .doesNotExist(expectedPath: promptsDir.path)
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: promptsDir.path)
            let txtFiles = contents.filter { $0.hasSuffix(".txt") }
            
            if txtFiles.isEmpty {
                return .existsButEmpty(path: promptsDir.path)
            } else {
                return .existsWithFiles(path: promptsDir.path, fileCount: txtFiles.count, files: txtFiles)
            }
        } catch {
            return .existsButUnreadable(path: promptsDir.path, error: error.localizedDescription)
        }
    }
}

// MARK: - Result Types

enum ExportResult {
    case success(message: String, exportedFiles: [String], directoryPath: String)
    case failure(String)
}

enum WriteResult {
    case success
    case failure(String)
}

enum DirectoryStatus {
    case doesNotExist(expectedPath: String)
    case existsButEmpty(path: String)
    case existsWithFiles(path: String, fileCount: Int, files: [String])
    case existsButUnreadable(path: String, error: String)
    
    var userMessage: String {
        switch self {
        case .doesNotExist(let path):
            return "Prompts directory does not exist.\nExpected location: \(path)"
        case .existsButEmpty(let path):
            return "Prompts directory exists but is empty.\nLocation: \(path)"
        case .existsWithFiles(let path, let count, _):
            return "Prompts directory exists with \(count) prompt files.\nLocation: \(path)"
        case .existsButUnreadable(let path, let error):
            return "Prompts directory exists but cannot be read.\nLocation: \(path)\nError: \(error)"
        }
    }
} 