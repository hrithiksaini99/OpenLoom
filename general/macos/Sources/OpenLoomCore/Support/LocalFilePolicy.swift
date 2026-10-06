import Foundation

public enum LocalFilePolicy {
    public static func requireLocalFile(_ url: URL) throws {
        guard url.isFileURL else { throw OpenLoomError.remoteURL }
        let parent = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        let values = try parent.resourceValues(forKeys: [.volumeIsLocalKey, .isUbiquitousItemKey])
        guard values.volumeIsLocal == true, values.isUbiquitousItem != true else {
            throw OpenLoomError.unsafePath
        }
    }

    public static func requireContained(_ url: URL, in root: URL) throws {
        guard url.isFileURL, root.isFileURL else { throw OpenLoomError.remoteURL }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        // Foundation may leave a path unresolved if its final component doesn't exist.
        // Resolve the nearest existing ancestor before appending future components.
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        while (try? FileManager.default.attributesOfItem(atPath: ancestor.path)) == nil {
            suffix.append(ancestor.lastPathComponent)
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { throw OpenLoomError.unsafePath }
            ancestor = parent
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: ancestor.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw OpenLoomError.unsafePath
        }
        var canonicalURL = ancestor.resolvingSymlinksInPath()
        for component in suffix.reversed() { canonicalURL.appendPathComponent(component) }
        let canonicalPath = canonicalURL.path
        guard canonicalPath.hasPrefix(canonicalRoot + "/") else { throw OpenLoomError.unsafePath }
        try requireLocalFile(url)
    }
}
