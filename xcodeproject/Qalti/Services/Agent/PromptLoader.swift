import Foundation
import Logging

/// Service responsible for loading prompts from custom files with fallback to defaults
class PromptLoader: Loggable {
    static let shared = PromptLoader()
    
    /// Optional override for prompts directory, used by CLI or advanced users
    private static var overrideDirectoryURL: URL?
    
    /// Set a custom prompts directory. Pass nil to clear override.
    static func setPromptsDirectoryOverride(_ url: URL?) {
        overrideDirectoryURL = url
    }
    
    private init() {}
    
    /// Get the prompts directory path
    private var promptsDirectoryURL: URL {
        if let override = Self.overrideDirectoryURL {
            return override
        }
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Qalti/.qalti/prompts")
    }
    
    /// Load a prompt from file, falling back to the provided default if file doesn't exist or is invalid
    /// - Parameters:
    ///   - fileName: Name of the prompt file (e.g., "system_prompt.txt")
    ///   - defaultContent: Default prompt content to use as fallback
    /// - Returns: The loaded prompt content
    /// - Throws: PromptLoaderError if file exists but is empty or malformed
    func loadPrompt(fileName: String, defaultContent: String) throws -> String {
        let fileURL = promptsDirectoryURL.appendingPathComponent(fileName)
        
        // Check if custom file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // File doesn't exist, use default
            return defaultContent
        }
        
        // File exists, try to load it
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            
            // Check if file is empty or only whitespace
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PromptLoaderError.emptyFile(fileName: fileName, filePath: fileURL.path)
            }
            
            return content
        } catch let error as PromptLoaderError {
            // Re-throw our custom errors
            throw error
        } catch {
            // File read error
            throw PromptLoaderError.unreadableFile(fileName: fileName, filePath: fileURL.path, underlyingError: error)
        }
    }
    
    /// Create the prompts directory if it doesn't exist
    func createPromptsDirectoryIfNeeded() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: promptsDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: promptsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                logger.debug("Created prompts directory at: \(promptsDirectoryURL.path)")
            } catch {
                logger.error("Failed to create prompts directory: \(error)")
            }
        }
    }
}

/// Errors that can occur during prompt loading
enum PromptLoaderError: LocalizedError {
    case emptyFile(fileName: String, filePath: String)
    case unreadableFile(fileName: String, filePath: String, underlyingError: Error)
    
    var errorDescription: String? {
        switch self {
        case .emptyFile(let fileName, let filePath):
            return "Custom prompt file '\(fileName)' is empty or contains only whitespace.\nFile path: \(filePath)\n\nPlease add content to the file or delete it to use the default prompt."
        case .unreadableFile(let fileName, let filePath, let underlyingError):
            return "Failed to read custom prompt file '\(fileName)'.\nFile path: \(filePath)\nError: \(underlyingError.localizedDescription)\n\nPlease check the file permissions and content, or delete it to use the default prompt."
        }
    }
} 