//
//  FileTreeView.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 02.06.2025.
//

import SwiftUI
import Foundation
import Logging
import Dispatch

// MARK: - Data Models

#if os(macOS)

/// Represents a file system item (file or folder)
struct FileSystemItem: Identifiable, Hashable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileSystemItem]?
    var isExpanded: Bool = false
    
    var displayName: String {
        name
    }
    
    var icon: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        } else {
            // Return appropriate icon based on file extension
            if url.lastPathComponent == ".qaltirules" {
                return "doc.text"
            }
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "swift":
                return "swift"
            case "txt", "md":
                return "doc.text"
            case "json", "test":
                return "doc.badge.gearshape"
            case "png", "jpg", "jpeg", "gif":
                return "photo"
            case "pdf":
                return "doc.richtext"
            default:
                return "doc"
            }
        }
    }
    
    // Helper method to create a new item with updated URL
    func withUpdatedURL(_ newURL: URL) -> FileSystemItem {
        FileSystemItem(
            name: newURL.lastPathComponent,
            url: newURL,
            isDirectory: self.isDirectory,
            children: self.children?.map { child in
                let childNewURL = newURL.appendingPathComponent(child.name)
                return child.withUpdatedURL(childNewURL)
            },
            isExpanded: self.isExpanded
        )
    }
    
    // Implement Equatable
    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.url == rhs.url &&
               lhs.isDirectory == rhs.isDirectory &&
               lhs.isExpanded == rhs.isExpanded &&
               lhs.children?.count == rhs.children?.count
    }
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(url)
        hasher.combine(isDirectory)
        hasher.combine(isExpanded)
    }
}

// MARK: - File System Watcher

private struct DirectoryWatcher {
    let url: URL
    let itemId: UUID
    let source: DispatchSourceFileSystemObject
    let fileDescriptor: Int32
}

// MARK: - View Model

@MainActor
class FileTreeViewModel: ObservableObject, Loggable {
    @Published var rootItems: [FileSystemItem] = []
    @Published var isLoading = false
    @Published var selectedFileURL: URL? = nil
    @Published var renamingItemID: UUID? = nil
    
    private let rootURL: URL
    private let onFileSelected: (URL) -> Void
    private let onFileRenamed: (URL, URL) -> Void
    private let onRunFolder: (URL) -> Void
    private var directoryWatchers: [UUID: DirectoryWatcher] = [:]
    private var disabledWatchers: Set<UUID> = []

    private let errorCapturer: ErrorCapturing
    private let onboardingManager: OnboardingManager

    init(
        rootURL: URL,
        errorCapturer: ErrorCapturing,
        onboardingManager: OnboardingManager,
        onFileSelected: @escaping (URL) -> Void,
        onFileRenamed: @escaping (URL, URL) -> Void,
        onRunFolder: @escaping (URL) -> Void
    ) {
        self.rootURL = rootURL
        self.errorCapturer = errorCapturer
        self.onboardingManager = onboardingManager
        self.onFileSelected = onFileSelected
        self.onFileRenamed = onFileRenamed
        self.onRunFolder = onRunFolder
        loadRootItems()
    }
    
    deinit {
        // Clean up all watchers
        Task { @MainActor in
            stopAllWatchers()
        }
    }
    
    func loadRootItems() {
        isLoading = true
        Task {
            let items = await loadItems(at: rootURL)
            await MainActor.run {
                self.rootItems = items
                self.isLoading = false
                
                // Start watching expanded directories
                let rootItem = FileSystemItem(
                    name: rootURL.lastPathComponent,
                    url: rootURL,
                    isDirectory: true,
                    children: items,
                    isExpanded: true
                )
                self.startWatching(directory: rootItem)
            }
        }
    }
    
    /// Refreshes the folder contents - useful when permissions change
    func refresh() {
        logger.debug("Refreshing folder contents")
        loadRootItems()
    }
    
    func toggleFolder(_ item: FileSystemItem) {
        let extraBounce = -0.15 * (1.0 - 1.0 / Double((item.children?.count ?? 0) + 1))

        // Always toggle the expanded state first
        withAnimation(.bouncy(duration: 0.3, extraBounce: extraBounce)) {
            updateItem(item) { updatedItem in
                var newItem = updatedItem
                newItem.isExpanded.toggle()
                
                // Handle watcher lifecycle based on expanded state
                if newItem.isExpanded {
                    // Start watching when expanding (if children are already loaded)
                    if newItem.children != nil {
                        self.startWatching(directory: newItem)
                    }
                }
                
                // If expanding and children haven't been loaded yet, load them
                if newItem.isExpanded && newItem.children == nil {
                    // Set empty array initially to prevent multiple loads
                    newItem.children = []
                    
                    // Load children asynchronously
                    Task {
                        let children = await self.loadItems(at: newItem.url)
                        await MainActor.run {
                            // Update with actual children
                            withAnimation(.bouncy(duration: 0.20, extraBounce: extraBounce)) {
                                self.updateItem(newItem) { itemToUpdate in
                                    var finalItem = itemToUpdate
                                    finalItem.children = children
                                    
                                    // Start watching this directory since it's now expanded with children
                                    if finalItem.isExpanded {
                                        self.startWatching(directory: finalItem)
                                        
                                        // Also start watching any subdirectories that are already expanded
                                        for child in children where child.isDirectory && child.isExpanded {
                                            self.startWatching(directory: child)
                                        }
                                    }
                                    
                                    return finalItem
                                }
                            }
                        }
                    }
                }
                
                return newItem
            }
        }
    }
    
    func selectFile(_ item: FileSystemItem) {
        guard !item.isDirectory else { return }
        selectedFileURL = item.url
        onFileSelected(item.url)
    }

    func runFolder(_ item: FileSystemItem) {
        guard item.isDirectory else { return }
        onRunFolder(item.url)
    }
    
    func startRenaming(_ item: FileSystemItem) {
        renamingItemID = item.id
    }
    
    func cancelRenaming() {
        renamingItemID = nil
    }
    
    func renameItem(_ item: FileSystemItem, to newName: String) {
        guard !newName.isEmpty && newName != item.name else {
            renamingItemID = nil
            return
        }
        
        // Find and disable watching for the parent directory
        let parentURL = item.url.deletingLastPathComponent()
        let parentItemId = findItemId(for: parentURL)
        if let parentId = parentItemId {
            disableWatching(for: parentId)
        }
        
        let oldURL = item.url
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            
            // Update item and its children with new URLs
            let updatedItem = item.withUpdatedURL(newURL)
            updateItem(item) { _ in updatedItem }
            
            // Update selectedFileURL if it was inside the renamed item
            if let selectedURL = selectedFileURL, selectedURL.path.hasPrefix(oldURL.path) {
                let relativePath = String(selectedURL.path.dropFirst(oldURL.path.count))
                let newSelectedURL = newURL.appendingPathComponent(relativePath)
                selectedFileURL = newSelectedURL
                
                // Notify the parent view of the file rename so TestEditingView can update its URL without reloading
                onFileRenamed(selectedURL, newSelectedURL)
            }
            
            // Re-enable watching for the parent directory
            if let parentId = parentItemId {
                enableWatching(for: parentId)
            }
            
            renamingItemID = nil
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Error renaming file: \(error)")
            // Re-enable watching even on error
            if let parentId = parentItemId {
                enableWatching(for: parentId)
            }
            // TODO: Show error alert to user
        }
    }
    
    func revealInFinder(_ item: FileSystemItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
    }
    
    func createNewFolder(in parentItem: FileSystemItem) {
        guard parentItem.isDirectory else { return }
        
        // Temporarily disable monitoring for this specific directory
        disableWatching(for: parentItem.id)
        
        let uniqueName = findUniqueName(baseName: "New Folder", in: parentItem.url, isDirectory: true)
        let newFolderURL = parentItem.url.appendingPathComponent(uniqueName)
        
        do {
            try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
            
            let newItem = FileSystemItem(
                name: uniqueName,
                url: newFolderURL,
                isDirectory: true,
                children: []
            )
            
            // Load existing children if folder wasn't expanded, then add new item
            Task {
                var existingChildren: [FileSystemItem] = []
                if parentItem.children == nil {
                    // Folder wasn't expanded - load existing children from filesystem
                    // But exclude the folder we just created to avoid duplicates
                    let allChildren = await self.loadItems(at: parentItem.url)
                    existingChildren = allChildren.filter { $0.url != newFolderURL }
                } else {
                    // Folder was already expanded - use existing children
                    existingChildren = parentItem.children ?? []
                }
                
                await MainActor.run {
                    // Add to parent's children and expand parent
                    self.updateItem(parentItem) { updatedParent in
                        var newParent = updatedParent
                        newParent.children = existingChildren
                        newParent.children?.append(newItem)
                        newParent.children = self.sortFileSystemItems(newParent.children ?? [], parentDirectoryName: newParent.name)
                        newParent.isExpanded = true
                        
                        // Start watching this directory since it's now expanded
                        if newParent.isExpanded {
                            self.startWatching(directory: newParent)
                        }
                        
                        return newParent
                    }
                    
                    // Re-enable monitoring immediately after the file operation
                    self.enableWatching(for: parentItem.id)
                    
                    // Put new item into rename mode
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.renamingItemID = newItem.id
                    }
                }
            }
            
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Error creating folder: \(error)")
            enableWatching(for: parentItem.id)
        }
    }
    
    func createNewTest(in parentItem: FileSystemItem) {
        guard parentItem.isDirectory else { return }

        // Check if this is special onboarding test creation
        let currentTip = onboardingManager.currentTipType
        let isFirstTest = currentTip == .createFirstTest

        // Temporarily disable monitoring for this specific directory
        disableWatching(for: parentItem.id)

        // Use special naming for onboarding tests, otherwise use unique naming
        let fileName: String
        let fileContent: String

        if isFirstTest {
            fileName = "First Test.test"
            fileContent = OnboardingSamples.advancedTestContent
        } else {
            fileName = findUniqueName(baseName: "New Test", in: parentItem.url, isDirectory: false, extension: "test")
            fileContent = ""
        }
        
        let newFileURL = parentItem.url.appendingPathComponent(fileName)
        
        do {
            try fileContent.write(to: newFileURL, atomically: true, encoding: .utf8)
            
            let newItem = FileSystemItem(
                name: fileName,
                url: newFileURL,
                isDirectory: false,
                children: nil
            )
            
            // Load existing children if folder wasn't expanded, then add new item
            Task {
                var existingChildren: [FileSystemItem] = []
                if parentItem.children == nil {
                    // Folder wasn't expanded - load existing children from filesystem
                    // But exclude the file we just created to avoid duplicates
                    let allChildren = await self.loadItems(at: parentItem.url)
                    existingChildren = allChildren.filter { $0.url != newFileURL }
                } else {
                    // Folder was already expanded - use existing children
                    existingChildren = parentItem.children ?? []
                }
                
                await MainActor.run {
                    // Add to parent's children and expand parent
                    self.updateItem(parentItem) { updatedParent in
                        var newParent = updatedParent
                        newParent.children = existingChildren
                        newParent.children?.append(newItem)
                        newParent.children = self.sortFileSystemItems(newParent.children ?? [], parentDirectoryName: newParent.name)
                        newParent.isExpanded = true
                        
                        // Start watching this directory since it's now expanded
                        if newParent.isExpanded {
                            self.startWatching(directory: newParent)
                        }
                        
                        return newParent
                    }
                    
                    // Re-enable monitoring immediately after the file operation
                    self.enableWatching(for: parentItem.id)
                    
                    if isFirstTest {
                        // For onboarding tests: auto-select them instead of renaming
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.selectedFileURL = newFileURL
                            self.onFileSelected(newFileURL)
                        }
                    } else {
                        // For subsequent tests: put into rename mode as before
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.renamingItemID = newItem.id
                        }
                    }
                    
                    // Handle onboarding markers
                    if isFirstTest {
                        onboardingManager.complete(.createFirstTest)
                    }
                }
            }
            
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Error creating test file: \(error)")
            enableWatching(for: parentItem.id)
        }
    }
    
    func createQaltiRules(in parentItem: FileSystemItem) {
        guard parentItem.isDirectory else { return }
        
        disableWatching(for: parentItem.id)
        
        let rulesURL = parentItem.url.appendingPathComponent(".qaltirules")
        let defaultContent = """
        # Test Rules
        """
        
        do {
            if !FileManager.default.fileExists(atPath: rulesURL.path) {
                try defaultContent.write(to: rulesURL, atomically: true, encoding: .utf8)
            }
            
            // Load children and update
            Task {
                var existingChildren: [FileSystemItem] = []
                if parentItem.children == nil {
                    let allChildren = await self.loadItems(at: parentItem.url)
                    existingChildren = allChildren.filter { $0.url != rulesURL }
                } else {
                    existingChildren = parentItem.children ?? []
                }
                
                let newItem = FileSystemItem(
                    name: ".qaltirules",
                    url: rulesURL,
                    isDirectory: false,
                    children: nil
                )
                
                await MainActor.run {
                    self.updateItem(parentItem) { updatedParent in
                        var newParent = updatedParent
                        newParent.children = existingChildren
                        // Avoid duplicates
                        if !(newParent.children ?? []).contains(where: { $0.url == rulesURL }) {
                            newParent.children?.append(newItem)
                        }
                        newParent.children = self.sortFileSystemItems(newParent.children ?? [], parentDirectoryName: newParent.name)
                        newParent.isExpanded = true
                        
                        // Start watching since it's expanded
                        if newParent.isExpanded {
                            self.startWatching(directory: newParent)
                        }
                        
                        return newParent
                    }
                    
                    // Re-enable monitoring
                    self.enableWatching(for: parentItem.id)
                    
                    // Select and open the rules file for editing
                    self.selectedFileURL = rulesURL
                    self.onFileSelected(rulesURL)
                }
            }
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Error creating .qaltirules: \(error)")
            enableWatching(for: parentItem.id)
        }
    }
    
    // MARK: - File System Monitoring
    
    private func startWatching(directory item: FileSystemItem) {
        guard item.isDirectory else { return }
        guard directoryWatchers[item.id] == nil else { return } // Already watching
        
        let fd = item.url.withUnsafeFileSystemRepresentation { (filenamePointer) -> Int32 in
            guard let filenamePointer = filenamePointer else { return -1 }
            return open(filenamePointer, O_EVTONLY)
        }
        
        guard fd >= 0 else {
            logger.error("Failed to open file descriptor for \(item.url.path)")
            return
        }
        
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        watcher.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Only process events if monitoring is not disabled for this item
                // and we're not currently renaming anything
                if !self.isWatchingDisabled(for: item.id) && self.renamingItemID != item.id {
                    self.handleDirectoryChange(for: item)
                }
            }
        }
        
        watcher.setCancelHandler {
            close(fd)
        }
        
        let directoryWatcher = DirectoryWatcher(
            url: item.url,
            itemId: item.id,
            source: watcher,
            fileDescriptor: fd
        )
        
        directoryWatchers[item.id] = directoryWatcher
        watcher.resume()
    }
    
    private func stopWatching(item: FileSystemItem) {
        guard let watcher = directoryWatchers[item.id] else { return }
        watcher.source.cancel()
        directoryWatchers.removeValue(forKey: item.id)
    }
    
    private func stopAllWatchers() {
        for watcher in directoryWatchers.values {
            watcher.source.cancel()
        }
        directoryWatchers.removeAll()
    }
    
    private func stopWatchingNestedDirectories(in item: FileSystemItem) {
        guard let children = item.children else { return }
        
        for child in children {
            if child.isDirectory {
                stopWatching(item: child)
                // Recursively stop watching nested directories
                stopWatchingNestedDirectories(in: child)
            }
        }
    }
    
    private func disableWatching(for itemId: UUID) {
        disabledWatchers.insert(itemId)
    }
    
    private func enableWatching(for itemId: UUID) {
        disabledWatchers.remove(itemId)
    }
    
    private func isWatchingDisabled(for itemId: UUID) -> Bool {
        return disabledWatchers.contains(itemId)
    }
    
    private func findItemId(for url: URL) -> UUID? {
        return findItemIdInArray(rootItems, targetURL: url)
    }
    
    private func findItemIdInArray(_ items: [FileSystemItem], targetURL: URL) -> UUID? {
        for item in items {
            if item.url == targetURL {
                return item.id
            }
            if let children = item.children,
               let foundId = findItemIdInArray(children, targetURL: targetURL) {
                return foundId
            }
        }
        return nil
    }
    
    private func handleDirectoryChange(for item: FileSystemItem) {
        // Reload the directory contents
        Task {
            let newChildren = await self.loadItems(at: item.url)
            
            await MainActor.run {
                // Update the item's children while preserving existing structure
                self.updateItem(item) { existingItem in
                    var updatedItem = existingItem
                    
                    // Preserve existing items' expanded states and IDs where possible
                    if let existingChildren = existingItem.children {
                        var mergedChildren: [FileSystemItem] = []
                        
                        for newChild in newChildren {
                            // Try to find existing item with same URL
                            if let existingChild = existingChildren.first(where: { $0.url == newChild.url }) {
                                // Preserve the existing item's state (ID, expanded state, etc.)
                                mergedChildren.append(existingChild)
                            } else {
                                // This is a new item
                                mergedChildren.append(newChild)
                            }
                        }
                        
                        updatedItem.children = mergedChildren
                    } else {
                        updatedItem.children = newChildren
                    }
                    
                    return updatedItem
                }
            }
        }
    }
    
    private func findUniqueName(baseName: String, in directory: URL, isDirectory: Bool, extension: String? = nil) -> String {
        let fileManager = FileManager.default
        var counter = 1
        var candidateName: String
        
        repeat {
            if counter == 1 {
                candidateName = baseName
            } else {
                candidateName = "\(baseName) (\(counter))"
            }
            
            if let ext = `extension` {
                candidateName += ".\(ext)"
            }
            
            let candidateURL = directory.appendingPathComponent(candidateName)
            
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateName
            }
            
            counter += 1
        } while counter < 1000 // Safety limit
        
        // Fallback with timestamp if we somehow hit the limit
        let timestamp = Int(Date().timeIntervalSince1970)
        candidateName = "\(baseName) (\(timestamp))"
        if let ext = `extension` {
            candidateName += ".\(ext)"
        }
        return candidateName
    }
    
    private func updateItem(_ targetItem: FileSystemItem, with updater: @escaping (FileSystemItem) -> FileSystemItem) {
        rootItems = updateItemInArray(rootItems, targetItem: targetItem, updater: updater)
    }
    
    private func updateItemInArray(_ items: [FileSystemItem], targetItem: FileSystemItem, updater: (FileSystemItem) -> FileSystemItem) -> [FileSystemItem] {
        return items.map { item in
            if item.id == targetItem.id {
                return updater(item)
            } else if let children = item.children {
                var updatedItem = item
                updatedItem.children = self.updateItemInArray(children, targetItem: targetItem, updater: updater)
                return updatedItem
            }
            return item
        }
    }
    
    private func sortFileSystemItems(_ items: [FileSystemItem], parentDirectoryName: String) -> [FileSystemItem] {
        let isRunsDirectory = parentDirectoryName == "Runs"

        return items.sorted { lhs, rhs in
            if !isRunsDirectory, lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return isRunsDirectory ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }
    
    private func loadItems(at url: URL) async -> [FileSystemItem] {
        do {
            let fileManager = FileManager.default
            // If the provided URL is a symlink, resolve it so we can list its contents
            // while still keeping displayed child URLs under the original (symlink) path.
            let listURL: URL
            if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                do {
                    let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                    listURL = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
                } catch {
                    // Fall back to the original URL if resolution fails
                    listURL = url
                }
            } else {
                listURL = url
            }

            let contents = try fileManager.contentsOfDirectory(
                at: listURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
            
            var items: [FileSystemItem] = []
            
            for fileURL in contents {
                let fileName = fileURL.lastPathComponent
                
                // Skip hidden files (starting with .) except for .qalti directory
                if fileName.hasPrefix(".") && fileName != ".qalti" && fileName != ".qaltirules" {
                    continue
                }
                
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                var isDirectory = resourceValues.isDirectory ?? false

                // If this is a symlink, resolve the destination and treat it as a
                // directory if the target is a directory.
                if resourceValues.isSymbolicLink == true {
                    let symlinkPath = fileURL.path
                    do {
                        let destination = try fileManager.destinationOfSymbolicLink(atPath: symlinkPath)
                        let resolvedURL = URL(
                            fileURLWithPath: destination,
                            relativeTo: fileURL.deletingLastPathComponent()
                        ).standardizedFileURL

                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDir) {
                            isDirectory = isDir.boolValue
                        }
                    } catch {
                        // If we fail to resolve, keep the original determination
                        // and just display as-is.
                    }
                }
                
                let item = FileSystemItem(
                    name: fileName,
                    // Map the child back under the original URL (which may be a symlink)
                    url: url.appendingPathComponent(fileName),
                    isDirectory: isDirectory,
                    children: nil
                )
                items.append(item)
            }
            
            // Sort: directories first, then files, both alphabetically
            return self.sortFileSystemItems(items, parentDirectoryName: url.lastPathComponent)
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Error loading directory contents: \(error)")
            return []
        }
    }
}

// MARK: - SwiftUI Views

struct FileTreeView: View {
    @EnvironmentObject private var errorCapturer: ErrorCapturerService
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @EnvironmentObject private var permissionService: PermissionService

    @StateObject private var viewModel: FileTreeViewModel
    private let statusProvider: ((URL) -> RunIndicatorStatus?)?
    
    init(
        rootURL: URL,
        errorCapturer: ErrorCapturing,
        onboardingManager: OnboardingManager,
        statusProvider: ((URL) -> RunIndicatorStatus?)? = nil,
        onFileSelected: @escaping (URL) -> Void,
        onFileRenamed: @escaping (URL, URL) -> Void = { _, _ in },
        onRunFolder: @escaping (URL) -> Void = { _ in }
    ) {
        self.statusProvider = statusProvider
        self._viewModel = StateObject(
            wrappedValue: FileTreeViewModel(
                rootURL: rootURL,
                errorCapturer: errorCapturer,
                onboardingManager: onboardingManager,
                onFileSelected: onFileSelected,
                onFileRenamed: onFileRenamed,
                onRunFolder: onRunFolder
            )
        )
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondaryLabel)
                    }
                    .padding()
                } else if shouldShowPermissionBanner {
                    PermissionBanner {
                        handlePermissionRefresh()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                } else {
                    ForEach(viewModel.rootItems) { item in
                        FileTreeItemView(
                            item: item,
                            level: 0,
                            selectedFileURL: viewModel.selectedFileURL,
                            renamingItemID: viewModel.renamingItemID,
                            statusProvider: statusProvider,
                            onToggle: { viewModel.toggleFolder($0) },
                            onSelect: { viewModel.selectFile($0) },
                            onStartRename: { viewModel.startRenaming($0) },
                            onRename: { item, newName in viewModel.renameItem(item, to: newName) },
                            onCancelRename: { viewModel.cancelRenaming() },
                            onRevealInFinder: { viewModel.revealInFinder($0) },
                            onCreateNewFolder: { viewModel.createNewFolder(in: $0) },
                            onCreateNewTest: { viewModel.createNewTest(in: $0) },
                            onRunFolder: { viewModel.runFolder($0) },
                            onCreateQaltiRules: { viewModel.createQaltiRules(in: $0) }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color.clear)
        .onAppear {
            // Start permission monitoring if folder is empty
            if shouldShowPermissionBanner {
                permissionService.startPermissionMonitoring()
            }
        }
        .onDisappear {
            // Stop monitoring when view disappears
            permissionService.stopPermissionMonitoring()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Determines whether to show the permission banner
    /// Shows when: folder is empty AND not loading AND permission service indicates no access
    private var shouldShowPermissionBanner: Bool {
        !viewModel.isLoading && 
        viewModel.rootItems.isEmpty && 
        !permissionService.hasDocumentsAccess
    }
    
    // MARK: - Private Methods
    
    /// Handles permission refresh requests from the banner
    private func handlePermissionRefresh() {
        permissionService.refreshPermissionStatus()
        viewModel.refresh()
    }
}

struct FileTreeItemView: View {
    let item: FileSystemItem
    let level: Int
    let selectedFileURL: URL?
    let renamingItemID: UUID?
    let statusProvider: ((URL) -> RunIndicatorStatus?)?
    let onToggle: (FileSystemItem) -> Void
    let onSelect: (FileSystemItem) -> Void
    let onStartRename: (FileSystemItem) -> Void
    let onRename: (FileSystemItem, String) -> Void
    let onCancelRename: () -> Void
    let onRevealInFinder: (FileSystemItem) -> Void
    let onCreateNewFolder: (FileSystemItem) -> Void
    let onCreateNewTest: (FileSystemItem) -> Void
    let onRunFolder: (FileSystemItem) -> Void
    let onCreateQaltiRules: (FileSystemItem) -> Void

    @EnvironmentObject private var onboardingManager: OnboardingManager

    @State private var isHovered = false
    @State private var renameText = ""
    
    private let indentationWidth: CGFloat = 20
    
    private var isRenaming: Bool {
        renamingItemID == item.id
    }

    private var runStatus: RunIndicatorStatus? {
        guard !item.isDirectory else { return nil }
        if item.url.lastPathComponent == ".qaltirules" { return nil }
        return statusProvider?(item.url.standardizedFileURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                // Background button for clicking on empty space
                Button(action: {
                    if !isRenaming {
                        if item.isDirectory {
                            onToggle(item)
                        } else {
                            onSelect(item)
                        }
                    }
                }) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRenaming)
                
                HStack(spacing: 6) {
                    // Indentation
                    if level > 0 {
                        Spacer()
                            .frame(width: CGFloat(level) * indentationWidth)
                    }
                    
                    // Folder expansion indicator
                    if item.isDirectory {
                        Button(action: {
                            if !isRenaming {
                                onToggle(item)
                            }
                        }) {
                            Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondaryLabel)
                                .frame(width: 12, height: 12)
                                .animation(.easeInOut(duration: 0.2), value: item.isExpanded)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isRenaming)
                    } else {
                        Spacer()
                            .frame(width: 12, height: 12)
                    }
                    
                    // Icon
                    Image(systemName: item.icon)
                        .font(.system(size: 14))
                        .foregroundColor(item.isDirectory ? .blue : .label)
                        .frame(width: 16, height: 16)
                        .animation(.easeInOut(duration: 0.2), value: item.isExpanded)
                        .allowsHitTesting(false)
                    
                    // Name or Text Field
                    if isRenaming {
                        HStack(spacing: 4) {
                            FileNameTextField(text: $renameText, onSubmit: {
                                onRename(item, renameText)
                            }, onCancel: {
                                onCancelRename()
                            })
                            .shadow(color: .label.opacity(0.4), radius: 4)
                            .padding(.vertical, -3)
                            .padding(.leading, -11)
                            .onAppear {
                                renameText = item.name
                            }
                            
                            Button(action: {
                                onRename(item, renameText)
                            }) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                    .frame(width: 17, height: 17)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.systemBackground)
                                            .shadow(color: .label.opacity(0.4), radius: 4)
                                    )
                                    .padding(.vertical, -3)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        Button(action: {
                            if item.isDirectory {
                                onToggle(item)
                            } else {
                                onSelect(item)
                            }
                        }) {
                            Text(item.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(.label)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer(minLength: 4)
                    statusIndicator
                }
                .if(item.isDirectory && (item.name == "Tests" || item.name == "Shared")) { view in
                    view
                        .onboardingTip(.createFirstTest)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .animation(.easeInOut(duration: 0.2), value: selectedFileURL)
                    .animation(.easeInOut(duration: 0.3), value: shouldHighlightForOnboarding)
            )
            .onHover { hovering in
                if !isRenaming {
                    isHovered = hovering
                }
            }
            .contextMenu {
                Button(action: {
                    onRevealInFinder(item)
                }) {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                
                Button(action: {
                    onStartRename(item)
                }) {
                    Label("Rename", systemImage: "pencil")
                }
                
                if item.isDirectory {
                    Button(action: {
                        onRunFolder(item)
                    }) {
                        Label("Run Folder", systemImage: "play.rectangle")
                    }

                    Divider()
                    
                    Button(action: {
                        onCreateNewFolder(item)
                    }) {
                        Label("New subfolder", systemImage: "folder.badge.plus")
                    }
                    
                    Button(action: {
                        onCreateNewTest(item)
                    }) {
                        Label("+ Add new test", systemImage: "doc.badge.plus")
                    }
                    
                    Button(action: {
                        onCreateQaltiRules(item)
                    }) {
                        Label("Create .qaltirules", systemImage: "doc.text")
                    }
                }
            }
            .onKeyPress(.escape) {
                if isRenaming {
                    onCancelRename()
                    return .handled
                }
                return .ignored
            }
            
            // Children (if expanded)
            if item.isDirectory && item.isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileTreeItemView(
                        item: child,
                        level: level + 1,
                        selectedFileURL: selectedFileURL,
                        renamingItemID: renamingItemID,
                        statusProvider: statusProvider,
                        onToggle: onToggle,
                        onSelect: onSelect,
                        onStartRename: onStartRename,
                        onRename: onRename,
                        onCancelRename: onCancelRename,
                        onRevealInFinder: onRevealInFinder,
                        onCreateNewFolder: onCreateNewFolder,
                        onCreateNewTest: onCreateNewTest,
                        onRunFolder: onRunFolder,
                        onCreateQaltiRules: onCreateQaltiRules
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if item.name == "Tests" {
                    AddNewTestButton(
                        item: item,
                        level: level,
                        indentationWidth: indentationWidth,
                        onCreateNewTest: onCreateNewTest
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
    
    private var isSelected: Bool {
        !item.isDirectory && selectedFileURL == item.url
    }
    
    private var backgroundFill: Color {
        if isSelected {
            return Color.secondarySystemFill
        } else if shouldHighlightForOnboarding {
            return Color.secondarySystemFill.opacity(0.66)
        } else if isHovered {
            return Color.secondarySystemFill.opacity(0.33)
        } else {
            return Color.clear
        }
    }
    
    private var shouldHighlightForOnboarding: Bool {
        guard item.isDirectory && (item.name == "Tests" || item.name == "Shared") else { return false }
        
        let currentTip = onboardingManager.currentTipType
        return currentTip == .createFirstTest
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if let status = runStatus {
            switch status.state {
            case .running:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .tint(Color.accentColor)
                    .frame(width: 16, height: 16)
            case .queued:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .tint(Color.secondaryLabel)
                    .frame(width: 16, height: 16)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)
            case .cancelled:
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondaryLabel)
                    .font(.system(size: 13))
                    .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - Add New Test Button

struct AddNewTestButton: View {
    let item: FileSystemItem
    let level: Int
    let indentationWidth: CGFloat
    let onCreateNewTest: (FileSystemItem) -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            onCreateNewTest(item)
        }) {
            HStack(spacing: 6) {
                // Indentation to match children
                if level >= 0 {
                    Spacer()
                        .frame(width: CGFloat(level + 1) * indentationWidth)
                }
                
                // Empty space for folder expansion indicator
                Spacer()
                    .frame(width: 12, height: 12)
                
                // Plus icon
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .frame(width: 16, height: 16)
                
                // Button text
                Text("Add new test")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondarySystemFill.opacity(0.33) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    let errorCapturer = PreviewServices.errorCapturer
    let onboarding = PreviewServices.onboarding

    FileTreeView(
        rootURL: URL(fileURLWithPath: "/Users"),
        errorCapturer: errorCapturer,
        onboardingManager: onboarding,
        onFileSelected: { url in
            print("Selected file: \(url)")
        }, onFileRenamed: { oldURL, newURL in
            print("File renamed from \(oldURL.path) to \(newURL.path)")
        }, onRunFolder: { url in
            print("Run folder: \(url)")
        })
    .environmentObject(errorCapturer)
    .environmentObject(onboarding)
    .frame(width: 300, height: 400)
}

#else
struct FileTreeView: View {

    init(
        rootURL: URL,
        statusProvider: ((URL) -> RunIndicatorStatus?)? = nil,
        onFileSelected: @escaping (URL) -> Void,
        onFileRenamed: @escaping (URL, URL) -> Void = { _, _ in },
        onRunFolder: @escaping (URL) -> Void = { _ in }
    ) {}

    var body: some View {
        Text("Not available on iOS")
    }
}
#endif
