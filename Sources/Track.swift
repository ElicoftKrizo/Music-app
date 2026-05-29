import Foundation
import UIKit
import AVFoundation

// MARK: - Track Model

struct Track: Identifiable, Codable {
    let id: UUID
    var title: String
    var artist: String

    // Filenames stored relative to this track's sandbox folder
    var audioFilename: String          // always present
    var hapticFilename: String?        // optional .ahap
    var videoFilename: String?         // optional .mp4
    var artworkFilename: String?       // optional cover image

    init(id: UUID = UUID(),
         title: String,
         artist: String,
         audioFilename: String,
         hapticFilename: String? = nil,
         videoFilename: String? = nil,
         artworkFilename: String? = nil) {
        self.id            = id
        self.title         = title
        self.artist        = artist
        self.audioFilename = audioFilename
        self.hapticFilename  = hapticFilename
        self.videoFilename   = videoFilename
        self.artworkFilename = artworkFilename
    }

    // MARK: Derived URLs

    var folder: URL { TrackStore.tracksDirectory.appendingPathComponent(id.uuidString) }

    var audioURL: URL    { folder.appendingPathComponent(audioFilename) }
    var hapticURL: URL?  { hapticFilename.map  { folder.appendingPathComponent($0) } }
    var videoURL: URL?   { videoFilename.map   { folder.appendingPathComponent($0) } }
    var artworkURL: URL? { artworkFilename.map { folder.appendingPathComponent($0) } }

    // MARK: Artwork loader

    func loadArtwork() -> UIImage? {
        guard let url = artworkURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Track Store (Data Controller)

@MainActor
final class TrackStore: ObservableObject {

    @Published var tracks: [Track] = []
    @Published var activeTrackID: UUID? = nil

    // MARK: Paths

    static var tracksDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Tracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }

    private static var indexURL: URL {
        tracksDirectory.appendingPathComponent("index.json")
    }

    // MARK: - Init

    init() { load() }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? JSONDecoder().decode([Track].self, from: data) else { return }
        tracks = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }

    // MARK: - Import a new track from picked URLs

    /// Creates a new Track entry, copies all files into an isolated folder,
    /// extracts metadata (title/artist/artwork), and appends to the list.
    func importTrack(audioURL: URL,
                     hapticURL: URL? = nil,
                     videoURL: URL? = nil,
                     coverURL: URL? = nil) async {
        let newID = UUID()
        let folder = Self.tracksDirectory.appendingPathComponent(newID.uuidString)
        try? FileManager.default.createDirectory(at: folder,
                                                  withIntermediateDirectories: true)

        // ── Copy audio ──────────────────────────────────────────────────────
        let audioFilename = "audio." + (audioURL.pathExtension.isEmpty ? "mp3" : audioURL.pathExtension)
        let destAudio = folder.appendingPathComponent(audioFilename)
        copySecure(from: audioURL, to: destAudio)

        // ── Extract metadata ─────────────────────────────────────────────────
        var title  = audioURL.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var artworkFilename: String? = nil

        let asset = AVURLAsset(url: destAudio)
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                if item.commonKey == .commonKeyTitle,
                   let t = try? await item.load(.stringValue), !t.isEmpty {
                    title = t
                }
                if item.commonKey == .commonKeyArtist,
                   let a = try? await item.load(.stringValue), !a.isEmpty {
                    artist = a
                }
            }
            // Embedded artwork
            let artItems = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .commonIdentifierArtwork
            )
            for artItem in artItems {
                if let data = try? await artItem.load(.dataValue),
                   UIImage(data: data) != nil {
                    let fn = "cover.png"
                    try? data.write(to: folder.appendingPathComponent(fn), options: .atomic)
                    artworkFilename = fn
                    break
                }
            }
        }

        // ── Manual cover fallback if no embedded art ──────────────────────
        if artworkFilename == nil, let coverURL = coverURL {
            let ext = coverURL.pathExtension.isEmpty ? "png" : coverURL.pathExtension
            let fn  = "cover.\(ext)"
            copySecure(from: coverURL, to: folder.appendingPathComponent(fn))
            artworkFilename = fn
        }

        // ── Optional haptic ───────────────────────────────────────────────
        var hapticFilename: String? = nil
        if let hapticURL = hapticURL {
            let fn = "haptic." + (hapticURL.pathExtension.isEmpty ? "ahap" : hapticURL.pathExtension)
            copySecure(from: hapticURL, to: folder.appendingPathComponent(fn))
            hapticFilename = fn
        }

        // ── Optional video ────────────────────────────────────────────────
        var videoFilename: String? = nil
        if let videoURL = videoURL {
            let fn = "canvas." + (videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension)
            copySecure(from: videoURL, to: folder.appendingPathComponent(fn))
            videoFilename = fn
        }

        let track = Track(id: newID,
                          title: title,
                          artist: artist,
                          audioFilename: audioFilename,
                          hapticFilename: hapticFilename,
                          videoFilename: videoFilename,
                          artworkFilename: artworkFilename)
        tracks.append(track)
        save()
    }

    // MARK: - Link optional files to an existing track

    func linkHaptic(url: URL, to trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let fn = "haptic." + (url.pathExtension.isEmpty ? "ahap" : url.pathExtension)
        copySecure(from: url, to: tracks[idx].folder.appendingPathComponent(fn))
        tracks[idx].hapticFilename = fn
        save()
    }

    func linkVideo(url: URL, to trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let fn = "canvas." + (url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
        copySecure(from: url, to: tracks[idx].folder.appendingPathComponent(fn))
        tracks[idx].videoFilename = fn
        save()
    }

    func linkCover(url: URL, to trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let fn = "cover." + (url.pathExtension.isEmpty ? "png" : url.pathExtension)
        copySecure(from: url, to: tracks[idx].folder.appendingPathComponent(fn))
        tracks[idx].artworkFilename = fn
        save()
    }

    // MARK: - Delete

    func delete(trackID: UUID) {
        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let folder = tracks[idx].folder
        try? FileManager.default.removeItem(at: folder)
        tracks.remove(at: idx)
        if activeTrackID == trackID { activeTrackID = tracks.first?.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { delete(trackID: tracks[$0].id) }
    }

    // MARK: - Helpers

    private func copySecure(from src: URL, to dst: URL) {
        let accessed = src.startAccessingSecurityScopedResource()
        defer { if accessed { src.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
    }
}
