import SwiftUI
import AVFoundation
import CoreHaptics
import UniformTypeIdentifiers

// MARK: - Lyric Model

struct LyricLine: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
}

// MARK: - File Picker Kind

enum FilePickerKind {
    case audio, haptic, video, cover
}

extension FilePickerKind: Identifiable {
    var id: Int {
        switch self { case .audio: return 0; case .haptic: return 1
                      case .video: return 2; case .cover:  return 3 }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let kind: FilePickerKind
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType]
        switch kind {
        case .audio:  types = [.audio, .mp3]
        case .haptic: types = [UTType(filenameExtension: "ahap") ?? .json, .json]
        case .video:  types = [.mpeg4Movie, .movie, .video]
        case .cover:  types = [.png, .jpeg, .heic, .image]
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Player State

@MainActor
final class PlayerState: ObservableObject {

    @Published var hasCanvasVideo: Bool   = false
    @Published var artworkImage: UIImage? = nil
    @Published var songTitle: String      = "Mr. Sunfish"
    @Published var artistName: String     = "YonKaGor"
    @Published var needsCoverFallback: Bool = false

    // AVQueuePlayer / Looper
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    var canvasPlayerLayer: AVPlayerLayer?

    // Audio
    private var audioPlayer: AVAudioPlayer?

    // Haptics
    private var hapticEngine: CHHapticEngine?
    private var hapticPatternPlayer: CHHapticAdvancedPatternPlayer?

    // Lyrics
    let lyrics: [LyricLine] = [
        LyricLine(timestamp: 0.00,  text: ""),
        LyricLine(timestamp: 2.50,  text: "Wake up, Mr. Sunfish"),
        LyricLine(timestamp: 6.10,  text: "Floating through the coral sea"),
        LyricLine(timestamp: 10.30, text: "Your scales catch the morning light"),
        LyricLine(timestamp: 14.80, text: "Swimming wild and free"),
        LyricLine(timestamp: 19.20, text: "Oh, Mr. Sunfish"),
        LyricLine(timestamp: 23.60, text: "Drift where the currents roam"),
        LyricLine(timestamp: 28.00, text: "A thousand miles from shore"),
        LyricLine(timestamp: 32.40, text: "The ocean is your home"),
        LyricLine(timestamp: 37.00, text: "Deep blue horizon calling"),
        LyricLine(timestamp: 41.50, text: "You rise to meet the sun"),
        LyricLine(timestamp: 46.00, text: "No road, no map, no compass"),
        LyricLine(timestamp: 50.30, text: "The current's never done"),
        LyricLine(timestamp: 55.00, text: "Oh, Mr. Sunfish"),
        LyricLine(timestamp: 59.40, text: "Drift where the currents roam"),
        LyricLine(timestamp: 63.80, text: "A thousand miles from shore"),
        LyricLine(timestamp: 68.20, text: "The ocean is your home"),
        LyricLine(timestamp: 72.60, text: ""),
    ]

    @Published var currentLyricText: String  = ""
    @Published var isPlaying: Bool           = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval    = 1.0
    @Published var sliderIsEditing: Bool     = false
    @Published var isShuffleOn: Bool         = false
    @Published var repeatMode: RepeatMode    = .off

    private var lyricTimer: Timer?

    enum RepeatMode: CaseIterable {
        case off, one, all
        var systemImageName: String {
            switch self { case .off: return "repeat"; case .one: return "repeat.1"; case .all: return "repeat" }
        }
        var isActive: Bool { self != .off }
    }

    // MARK: - Init

    init() {
        setupAudioSession()
        prepareHaptics()
        loadLegacySandboxIfNeeded()
    }

    // Boot: load old single-track sandbox files so existing users aren't broken
    private func loadLegacySandboxIfNeeded() {
        let audio = resolveURL(sandbox: FileManager.sandboxAudioURL,
                               bundleResource: "music", ext: "mp3")
        loadAudio(from: audio)
        if let h = resolveURL(sandbox: FileManager.sandboxHapticURL,
                               bundleResource: "haptic", ext: "ahap") {
            loadHapticPattern(from: h)
        }
        let vid = FileManager.sandboxVideoURL
        if FileManager.default.fileExists(atPath: vid.path) {
            hasCanvasVideo = true; setupCanvasPlayer(url: vid)
        } else if let bv = Bundle.main.url(forResource: "canvas", withExtension: "mp4") {
            hasCanvasVideo = true; setupCanvasPlayer(url: bv)
        }
        loadArtworkFromURL(FileManager.sandboxCoverURL)
            ?? loadBundleCover()
        if let audio = audio {
            Task { await resolveArtwork(from: audio) }
        }
    }

    private func resolveURL(sandbox: URL, bundleResource: String, ext: String) -> URL? {
        FileManager.default.fileExists(atPath: sandbox.path)
            ? sandbox
            : Bundle.main.url(forResource: bundleResource, withExtension: ext)
    }

    // MARK: - Load from Track (TrackManager selection)

    func load(track: Track) {
        let wasPlaying = isPlaying
        if wasPlaying { togglePlayPause() }
        currentTime = 0

        songTitle  = track.title
        artistName = track.artist

        // Audio
        loadAudio(from: track.audioURL)

        // Haptic
        if let hURL = track.hapticURL,
           FileManager.default.fileExists(atPath: hURL.path) {
            loadHapticPattern(from: hURL)
        }

        // Video
        if let vURL = track.videoURL,
           FileManager.default.fileExists(atPath: vURL.path) {
            hasCanvasVideo = true
            setupCanvasPlayer(url: vURL)
        } else {
            hasCanvasVideo = false
            queuePlayer?.pause()
            playerLooper = nil; queuePlayer = nil; canvasPlayerLayer = nil
        }

        // Artwork
        if let art = track.loadArtwork() {
            artworkImage = art
            needsCoverFallback = false
        } else {
            artworkImage = nil
            needsCoverFallback = true
        }

        if wasPlaying { togglePlayPause() }
    }

    // MARK: - Audio

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func loadAudio(from url: URL?) {
        guard let url = url else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 1.0
        } catch { print("AVAudioPlayer: \(error)") }
    }

    // MARK: - Canvas Video

    private func setupCanvasPlayer(url: URL) {
        queuePlayer?.pause()
        playerLooper = nil; queuePlayer = nil; canvasPlayerLayer = nil
        let item   = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true; player.volume = 0
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer  = player
        let layer    = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        canvasPlayerLayer  = layer
        player.play()
    }

    // MARK: - Haptics

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.playsHapticsOnly = false
            hapticEngine?.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in try? self?.hapticEngine?.start() }
            }
            try hapticEngine?.start()
        } catch { print("CHHapticEngine: \(error)") }
    }

    private func loadHapticPattern(from url: URL) {
        guard let engine = hapticEngine else { return }
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let pat  = try CHHapticPattern(dictionary: json)
            hapticPatternPlayer = try engine.makeAdvancedPlayer(with: pat)
            hapticPatternPlayer?.loopEnabled = false
        } catch { print("Haptic load: \(error)") }
    }

    private func seekHapticTo(offset: TimeInterval) {
        try? hapticPatternPlayer?.seek(toOffset: offset)
    }

    // MARK: - Artwork helpers

    @discardableResult
    private func loadArtworkFromURL(_ url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img  = UIImage(data: data) else { return nil }
        artworkImage = img
        return img
    }

    @discardableResult
    private func loadBundleCover() -> UIImage? {
        for ext in ["png", "jpg"] {
            if let url = Bundle.main.url(forResource: "cover", withExtension: ext),
               let img = loadArtworkFromURL(url) { return img }
        }
        return nil
    }

    private func resolveArtwork(from audioURL: URL) async {
        let asset = AVURLAsset(url: audioURL)
        guard let metadata = try? await asset.load(.commonMetadata) else {
            needsCoverFallback = true; return
        }
        let items = AVMetadataItem.metadataItems(from: metadata,
                                                  filteredByIdentifier: .commonIdentifierArtwork)
        for item in items {
            if let data  = try? await item.load(.dataValue),
               let image = UIImage(data: data) {
                artworkImage = image
                try? image.pngData()?.write(to: FileManager.sandboxCoverURL, options: .atomic)
                needsCoverFallback = false
                return
            }
        }
        needsCoverFallback = true
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        guard let audio = audioPlayer else { return }
        if audio.isPlaying {
            audio.pause(); isPlaying = false
            stopHapticPlayer(); stopLyricTimer()
        } else {
            audio.play(); isPlaying = true
            seekHapticTo(offset: audio.currentTime)
            startHapticPlayer(); startLyricTimer()
        }
        triggerTransientHaptic()
    }

    func skipForward() {
        guard let a = audioPlayer else { return }
        let t = min(a.currentTime + 15, a.duration)
        a.currentTime = t; currentTime = t
        seekHapticTo(offset: t); triggerTransientHaptic()
    }

    func skipBack() {
        guard let a = audioPlayer else { return }
        let t = max(a.currentTime - 15, 0)
        a.currentTime = t; currentTime = t
        seekHapticTo(offset: t); triggerTransientHaptic()
    }

    func seekTo(time: TimeInterval) {
        guard let a = audioPlayer else { return }
        a.currentTime = time; currentTime = time
        seekHapticTo(offset: time); triggerTransientHaptic()
    }

    func toggleShuffle() { isShuffleOn.toggle(); triggerTransientHaptic() }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        repeatMode = all[((all.firstIndex(of: repeatMode) ?? 0) + 1) % all.count]
        triggerTransientHaptic()
    }

    private func startHapticPlayer()  { try? hapticPatternPlayer?.start(atTime: CHHapticTimeImmediate) }
    private func stopHapticPlayer()   { try? hapticPatternPlayer?.stop(atTime: CHHapticTimeImmediate) }

    private func triggerTransientHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        let ev = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            ],
            relativeTime: 0
        )
        guard let pat    = try? CHHapticPattern(events: [ev], parameters: []),
              let player = try? engine.makePlayer(with: pat) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    // MARK: - Lyric Timer

    func startLyricTimer() {
        stopLyricTimer()
        lyricTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickLyricClock() }
        }
        RunLoop.main.add(lyricTimer!, forMode: .common)
    }

    func stopLyricTimer() { lyricTimer?.invalidate(); lyricTimer = nil }

    private func tickLyricClock() {
        guard let a = audioPlayer else { return }
        let t = a.currentTime
        if !sliderIsEditing { currentTime = t }
        currentLyricText = lyrics.last(where: { $0.timestamp <= t })?.text ?? ""
    }

    func cleanup() {
        stopLyricTimer(); stopHapticPlayer(); hapticEngine?.stop()
        audioPlayer?.stop(); queuePlayer?.pause()
    }
}

// MARK: - Canvas Video View

struct CanvasVideoView: UIViewRepresentable {
    let playerLayer: AVPlayerLayer?
    func makeUIView(context: Context) -> UIView {
        let v = PassthroughVideoView(); v.backgroundColor = .black; return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer = playerLayer else { return }
        layer.frame = uiView.bounds
        if layer.superlayer == nil { uiView.layer.addSublayer(layer) }
    }
}

final class PassthroughVideoView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.forEach { $0.frame = bounds }
    }
}

// MARK: - Album Artwork View

struct AlbumArtworkView: View {
    let cornerRadius: CGFloat
    let size: CGFloat
    let image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.45, green: 0.10, blue: 0.18),
                            Color(red: 0.25, green: 0.05, blue: 0.10),
                        ]),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .resizable().scaledToFit()
                        .padding(size * 0.25)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Time Formatter

private func formatTime(_ t: TimeInterval) -> String {
    guard t.isFinite, !t.isNaN, t >= 0 else { return "0:00" }
    let i = Int(t)
    return String(format: "%d:%02d", i / 60, i % 60)
}

// MARK: - Player Controls Bar

struct PlayerControlsBar: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { state.duration > 0 ? state.currentTime / state.duration : 0 },
                        set: { state.currentTime = $0 * state.duration }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        state.sliderIsEditing = editing
                        if !editing { state.seekTo(time: state.currentTime) }
                    }
                )
                .accentColor(.white).padding(.horizontal, 4)
                HStack {
                    Text(formatTime(state.currentTime))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("-\(formatTime(max(0, state.duration - state.currentTime)))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 4)
            }
            HStack(spacing: 0) {
                Button(action: { state.toggleShuffle() }) {
                    Image(systemName: "shuffle").font(.system(size: 18))
                        .foregroundColor(state.isShuffleOn ? .white : .white.opacity(0.45))
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Button(action: { state.skipBack() }) {
                    Image(systemName: "backward.fill").font(.system(size: 28))
                        .foregroundColor(.white).frame(width: 52, height: 52)
                }
                Spacer()
                Button(action: { state.togglePlayPause() }) {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 64, height: 64)
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold)).foregroundColor(.black)
                            .offset(x: state.isPlaying ? 0 : 2)
                    }
                }.shadow(color: .white.opacity(0.2), radius: 10)
                Spacer()
                Button(action: { state.skipForward() }) {
                    Image(systemName: "forward.fill").font(.system(size: 28))
                        .foregroundColor(.white).frame(width: 52, height: 52)
                }
                Spacer()
                Button(action: { state.cycleRepeat() }) {
                    Image(systemName: state.repeatMode.systemImageName).font(.system(size: 18))
                        .foregroundColor(state.repeatMode.isActive ? .white : .white.opacity(0.45))
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Cover Fallback Banner

struct CoverFallbackBanner: View {
    @ObservedObject var state: PlayerState
    @State private var pickerShown = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark").foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("No embedded artwork").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Text("Tap to pick an image").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button("Pick Image") { pickerShown = true }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white).clipShape(Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
        .sheet(isPresented: $pickerShown) {
            DocumentPicker(kind: .cover) { url in
                let dest = FileManager.sandboxCoverURL
                let acc  = url.startAccessingSecurityScopedResource()
                defer { if acc { url.stopAccessingSecurityScopedResource() } }
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
                if let data = try? Data(contentsOf: dest) { state.artworkImage = UIImage(data: data) }
                state.needsCoverFallback = false
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var playerState = PlayerState()
    @StateObject private var trackStore  = TrackStore()
    @State private var showTrackManager  = false

    var body: some View {
        ZStack {
            if playerState.hasCanvasVideo { canvasLayout } else { fallbackLayout }
        }
        .preferredColorScheme(.dark)
        .onDisappear { playerState.cleanup() }
        .sheet(isPresented: $showTrackManager) {
            TrackManagerView(store: trackStore) { track in
                playerState.load(track: track)
                showTrackManager = false
            }
        }
    }

    // MARK: - Track Manager button overlay (top-right)

    private var managerButtonOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    showTrackManager = true
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .padding(.top, 56)
                .padding(.trailing, 20)
            }
            Spacer()
        }
    }

    // MARK: - Layout A: Canvas Video

    private var canvasLayout: some View {
        ZStack {
            CanvasVideoView(playerLayer: playerState.canvasPlayerLayer)
                .ignoresSafeArea(.all)
            Color.black.opacity(0.35).ignoresSafeArea(.all)

            VStack(spacing: 0) {
                Spacer()
                if !playerState.currentLyricText.isEmpty {
                    Text(playerState.currentLyricText)
                        .font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .id(playerState.currentLyricText)
                        .animation(.easeInOut(duration: 0.25), value: playerState.currentLyricText)
                }
                Spacer()
                if playerState.needsCoverFallback {
                    CoverFallbackBanner(state: playerState).padding(.bottom, 12)
                }
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        AlbumArtworkView(cornerRadius: 10, size: 56, image: playerState.artworkImage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playerState.songTitle)
                                .font(.system(size: 17, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            Text(playerState.artistName)
                                .font(.system(size: 14)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24).padding(.bottom, 16)
                    PlayerControlsBar(state: playerState)
                        .padding(.horizontal, 24).padding(.bottom, 40)
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.80)]),
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            managerButtonOverlay
        }
    }

    // MARK: - Layout B: Fallback Gradient

    private var fallbackLayout: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.22, green: 0.04, blue: 0.09),
                    Color(red: 0.10, green: 0.02, blue: 0.05),
                    Color(red: 0.05, green: 0.01, blue: 0.03),
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea(.all)

            VStack(spacing: 0) {
                Spacer(minLength: 48)
                AlbumArtworkView(
                    cornerRadius: 20,
                    size: min(UIScreen.main.bounds.width * 0.72, 320),
                    image: playerState.artworkImage
                )
                .padding(.bottom, 32)
                VStack(spacing: 6) {
                    Text(playerState.songTitle)
                        .font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text(playerState.artistName)
                        .font(.system(size: 16)).foregroundColor(.white.opacity(0.70))
                }
                .padding(.bottom, 20)
                if playerState.needsCoverFallback {
                    CoverFallbackBanner(state: playerState).padding(.bottom, 16)
                }
                ZStack {
                    if !playerState.currentLyricText.isEmpty {
                        Text(playerState.currentLyricText)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                            .transition(.opacity)
                            .id(playerState.currentLyricText)
                            .animation(.easeInOut(duration: 0.25), value: playerState.currentLyricText)
                    } else { Color.clear }
                }
                .frame(minHeight: 28).padding(.bottom, 28)
                Spacer()
                PlayerControlsBar(state: playerState)
                    .padding(.horizontal, 24).padding(.bottom, 52)
            }
            managerButtonOverlay
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().previewDevice(PreviewDevice(rawValue: "iPhone 15 Pro"))
    }
}
#endif
