import Foundation

// MARK: - Sandbox file persistence helpers
// All dynamic user-selected assets are copied into the app's
// Application Support directory so they survive app restarts.

extension FileManager {

    // MARK: Base directory

    static var sandboxDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("DynamicAssets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return dir
    }

    // MARK: Well-known sandbox paths

    static var sandboxAudioURL: URL {
        sandboxDirectory.appendingPathComponent("music.mp3")
    }
    static var sandboxHapticURL: URL {
        sandboxDirectory.appendingPathComponent("haptic.ahap")
    }
    static var sandboxVideoURL: URL {
        sandboxDirectory.appendingPathComponent("canvas.mp4")
    }
    static var sandboxCoverURL: URL {
        sandboxDirectory.appendingPathComponent("cover.png")
    }

    // MARK: Copy helper

    /// Copies `sourceURL` (which may be a security-scoped URL) to
    /// `destinationURL` inside the sandbox, overwriting any previous copy.
    static func copyToSandbox(from sourceURL: URL, to destinationURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    // MARK: Remove helpers

    static func removeSandboxAudio() { try? FileManager.default.removeItem(at: sandboxAudioURL) }
    static func removeSandboxHaptic() { try? FileManager.default.removeItem(at: sandboxHapticURL) }
    static func removeSandboxVideo()  { try? FileManager.default.removeItem(at: sandboxVideoURL) }
    static func removeSandboxCover()  { try? FileManager.default.removeItem(at: sandboxCoverURL) }
}
