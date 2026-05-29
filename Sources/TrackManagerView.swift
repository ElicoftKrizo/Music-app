import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Import State (drives multi-step sheet flow)

private enum ImportStep: Identifiable {
    case audio                          // Step 1: always required
    case optionalFiles(audioURL: URL)   // Step 2: haptic / video / cover
    case coverFallback(audioURL: URL, hapticURL: URL?, videoURL: URL?)  // Step 3: no embedded art

    var id: String {
        switch self {
        case .audio:          return "audio"
        case .optionalFiles:  return "optionalFiles"
        case .coverFallback:  return "coverFallback"
        }
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let track: Track
    let isActive: Bool
    @State private var artwork: UIImage? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.15))
                if let img = artwork {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 52, height: 52)

            // Metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Status badges
                HStack(spacing: 6) {
                    if track.hapticFilename != nil {
                        StatusBadge(label: "AHAP", color: .purple)
                    }
                    if track.videoFilename != nil {
                        StatusBadge(label: "MP4", color: .blue)
                    }
                }
            }

            Spacer()

            // Playing indicator
            if isActive {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
            }
        }
        .padding(.vertical, 4)
        .onAppear { artwork = track.loadArtwork() }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color.opacity(0.6), lineWidth: 1)
            )
    }
}

// MARK: - Optional Files Sheet
// Shown after audio is picked — lets user attach .ahap, .mp4, cover

private struct OptionalFilesSheet: View {
    let audioURL: URL
    @ObservedObject var store: TrackStore
    @Binding var step: ImportStep?
    @State private var hapticURL: URL? = nil
    @State private var videoURL:  URL? = nil
    @State private var coverURL:  URL? = nil
    @State private var pickerTarget: FilePickerKind? = nil
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("Required") {
                    fileRow(icon: "waveform", label: audioURL.lastPathComponent,
                            attached: true, color: .green)
                }
                Section("Optional") {
                    Button {
                        pickerTarget = .haptic
                    } label: {
                        fileRow(icon: "hand.tap", label: hapticURL?.lastPathComponent ?? "Add Haptic Pattern (.ahap)",
                                attached: hapticURL != nil, color: .purple)
                    }
                    Button {
                        pickerTarget = .video
                    } label: {
                        fileRow(icon: "film", label: videoURL?.lastPathComponent ?? "Add Canvas Video (.mp4)",
                                attached: videoURL != nil, color: .blue)
                    }
                    Button {
                        pickerTarget = .cover
                    } label: {
                        fileRow(icon: "photo", label: coverURL?.lastPathComponent ?? "Add Album Artwork",
                                attached: coverURL != nil, color: .orange)
                    }
                }
            }
            .navigationTitle("Link Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { step = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Importing…" : "Import") {
                        Task { await doImport() }
                    }
                    .disabled(isImporting)
                }
            }
            .sheet(item: $pickerTarget) { kind in
                DocumentPicker(kind: kind) { url in
                    switch kind {
                    case .haptic: hapticURL = url
                    case .video:  videoURL  = url
                    case .cover:  coverURL  = url
                    default: break
                    }
                }
            }
        }
    }

    @MainActor
    private func doImport() async {
        isImporting = true
        // If user provided explicit cover, skip embedded-art check for cover
        await store.importTrack(audioURL: audioURL,
                                hapticURL: hapticURL,
                                videoURL: videoURL,
                                coverURL: coverURL)
        // Check if the newly added track lacks artwork and no manual cover was given
        if coverURL == nil, store.tracks.last?.artworkFilename == nil {
            step = .coverFallback(audioURL: audioURL, hapticURL: hapticURL, videoURL: videoURL)
        } else {
            step = nil
        }
        isImporting = false
    }

    private func fileRow(icon: String, label: String, attached: Bool, color: Color) -> some View {
        Label {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(attached ? .primary : .secondary)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundColor(attached ? color : .secondary)
        }
    }
}

// MARK: - Cover Fallback Sheet

private struct CoverFallbackSheet: View {
    @ObservedObject var store: TrackStore
    @Binding var step: ImportStep?
    @State private var pickerShown = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("No Embedded Artwork")
                    .font(.title2.bold())
                Text("This audio file has no embedded cover art.\nPick an image file or skip.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Pick Image File") { pickerShown = true }
                    .buttonStyle(.borderedProminent)
                Button("Skip") { step = nil }
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("Album Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $pickerShown) {
                DocumentPicker(kind: .cover) { url in
                    if let id = store.tracks.last?.id {
                        store.linkCover(url: url, to: id)
                    }
                    step = nil
                }
            }
        }
    }
}

// MARK: - Track Manager View

struct TrackManagerView: View {
    @ObservedObject var store: TrackStore
    /// Called when the user taps a row — host (ContentView) acts on this
    let onSelect: (Track) -> Void

    @State private var importStep: ImportStep? = nil
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            Group {
                if store.tracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
            }
            .navigationTitle("Track Manager")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        importStep = .audio
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .environment(\.editMode, $editMode)
            // ── Import flow sheets ────────────────────────────────────────
            .sheet(item: $importStep) { step in
                switch step {
                case .audio:
                    DocumentPicker(kind: .audio) { url in
                        importStep = .optionalFiles(audioURL: url)
                    }
                case .optionalFiles(let audioURL):
                    OptionalFilesSheet(audioURL: audioURL,
                                       store: store,
                                       step: $importStep)
                case .coverFallback:
                    CoverFallbackSheet(store: store, step: $importStep)
                }
            }
        }
    }

    // MARK: Track List

    private var trackList: some View {
        List {
            ForEach(store.tracks) { track in
                Button {
                    store.activeTrackID = track.id
                    onSelect(track)
                } label: {
                    TrackRow(track: track, isActive: store.activeTrackID == track.id)
                }
                .buttonStyle(.plain)
                // Per-row swipe actions
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.delete(trackID: track.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        importStep = .optionalFiles(audioURL: track.audioURL)
                    } label: {
                        Label("Link Files", systemImage: "link")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        importStep = .optionalFiles(audioURL: track.audioURL)
                    } label: {
                        Label("Link Haptic / Video / Cover", systemImage: "link")
                    }
                    Button(role: .destructive) {
                        store.delete(trackID: track.id)
                    } label: {
                        Label("Delete Track", systemImage: "trash")
                    }
                }
            }
            .onDelete { store.delete(at: $0) }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No Tracks Yet")
                .font(.title2.bold())
            Text("Tap + to import your first audio file.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Import Track") { importStep = .audio }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
struct TrackManagerView_Previews: PreviewProvider {
    static var previews: some View {
        TrackManagerView(store: TrackStore(), onSelect: { _ in })
    }
}
#endif
