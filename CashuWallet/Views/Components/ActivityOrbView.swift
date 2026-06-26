import SwiftUI
import UIKit
import ImageIO
import CryptoKit

// MARK: - Activity Orb View
/// Loading indicator showing a subtle pulsing indicator when operations are in progress

struct ActivityOrbView: View {
    @Binding var isActive: Bool
    var autoHideDelay: Double = 2.0

    @State private var isVisible: Bool = false
    @State private var rotation: Double = 0

    var body: some View {
        Group {
            if isVisible {
                Image(systemName: "circle.dotted")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(rotation))
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: isActive) { _, newValue in
            if newValue {
                showOrb()
            } else {
                hideOrbAfterDelay()
            }
        }
    }

    private func showOrb() {
        withAnimation(.easeIn(duration: 0.3)) {
            isVisible = true
        }
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func hideOrbAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay) {
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = false
                rotation = 0
            }
        }
    }
}

// MARK: - Loading Spinner View
/// Full-screen loading spinner for operations — uses standard ProgressView

struct LoadingSpinnerView: View {
    var message: String?

    var body: some View {
        if let message = message {
            ProgressView(message)
        } else {
            ProgressView()
        }
    }
}

// MARK: - Native Empty State

struct NativeEmptyState: View {
    enum Style {
        case fullScreen
        case section
        case compact

        var iconSize: CGFloat {
            switch self {
            case .fullScreen: return 56
            case .section: return 42
            case .compact: return 30
            }
        }

        var titleFont: Font {
            switch self {
            case .fullScreen: return .title2.weight(.semibold)
            case .section: return .headline.weight(.semibold)
            case .compact: return .subheadline.weight(.semibold)
            }
        }

        var descriptionFont: Font {
            switch self {
            case .fullScreen: return .body
            case .section, .compact: return .subheadline
            }
        }

        var spacing: CGFloat {
            switch self {
            case .fullScreen: return 12
            case .section: return 10
            case .compact: return 8
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .fullScreen: return 0
            case .section: return 32
            case .compact: return 24
            }
        }

        var maxHeight: CGFloat? {
            switch self {
            case .fullScreen: return .infinity
            case .section, .compact: return nil
            }
        }
    }

    let title: String
    let systemImage: String
    var description: String?
    var style: Style = .fullScreen

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var symbolTrigger = false

    var body: some View {
        VStack(spacing: style.spacing) {
            animatedIcon

            VStack(spacing: 4) {
                Text(title)
                    .font(style.titleFont)
                    .multilineTextAlignment(.center)

                if let description {
                    Text(description)
                        .font(style.descriptionFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: style.maxHeight)
        .padding(.horizontal, 32)
        .padding(.vertical, style.verticalPadding)
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (isPresented ? 1 : 0.96))
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isPresented)
        .task {
            isPresented = true
            guard !reduceMotion else { return }
            symbolTrigger.toggle()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var animatedIcon: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: style.iconSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .opacity(0.62)

        if #available(iOS 17.0, macOS 14.0, *) {
            icon.symbolEffect(.bounce, value: symbolTrigger)
        } else {
            icon
        }
    }
}

// MARK: - Global Mutex Lock Overlay
/// Overlay shown when wallet is performing critical operations

struct MutexLockOverlay: View {
    @Binding var isLocked: Bool
    var message: String = "Processing..."

    var body: some View {
        Group {
            if isLocked {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)

                        Text(message)
                            .font(.headline)
                    }
                    .padding(40)
                    .liquidGlassMaterial(in: RoundedRectangle(cornerRadius: 20), material: .regularMaterial)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }
}

// MARK: - Suggested Mints (restore recognition aid)

/// A known public mint surfaced as a one-tap quick-add during onboarding and
/// seed-restore.
struct RecommendedMint: Identifiable {
    let name: String
    let url: String
    /// Curated logo for the suggestion avatar. These mints aren't tracked yet,
    /// so there's no fetched `MintInfo.iconUrl` to fall back on — we ship the
    /// published `/v1/info` icon for each. A miss degrades to the monogram in
    /// `MintAvatarView`, so a stale URL never breaks the row.
    var iconUrl: String? = nil
    var id: String { url }

    /// The curated shortlist offered when a user has no mints to type from memory.
    static let suggested: [RecommendedMint] = [
        RecommendedMint(name: "Minibits", url: "https://mint.minibits.cash/Bitcoin", iconUrl: "https://minibits.cash/icon-192.png"),
        RecommendedMint(name: "Coinos", url: "https://mint.coinos.io", iconUrl: "https://coinos.io/images/icon.png"),
        RecommendedMint(name: "Macadamia", url: "https://mint.macadamia.cash", iconUrl: "https://cypherbase.cc/images/logo_w256.png")
    ]
}

// MARK: - Mint Avatar

/// Circular mint avatar — the mint's published logo when available, otherwise a
/// tinted monogram of its initial (the Contacts / Wallet idiom) rather than a
/// generic glyph, so each mint reads as distinct. Loads via `AsyncImage`,
/// matching the app's other mint-icon sites; the monogram also covers the
/// loading and failure phases. Used by the onboarding first-mint picker and the
/// suggested-mints quick-add.
struct MintAvatarView: View {
    let iconUrl: String?
    let name: String
    var size: CGFloat = 36

    private var monogram: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        return String(first).uppercased()
    }

    var body: some View {
        Group {
            if let iconUrl, let url = URL(string: iconUrl) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay(
                Text(monogram)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            )
    }
}

/// Quick-add suggestion rows shown in the restore-mints flow. Converts the
/// "type a mint URL from memory" recall task into recognition. Shows the
/// wallet's own mints first ("Your mints"), then falls back to curated
/// suggestions for users who have none configured yet. Rows sit on the bare
/// canvas with hairline dividers — the same shape as the staged-mint list.
struct SuggestedMintsSection: View {
    /// URLs already staged or restored — filtered out of the suggestions.
    let existingURLs: Set<String>
    let onAdd: (String) -> Void
    /// Mints already configured in the wallet — surfaced first so users
    /// recognise them without having to remember URLs.
    var walletMints: [RecommendedMint] = []

    private var availableWalletMints: [RecommendedMint] {
        walletMints.filter { !existingURLs.contains($0.url) }
    }

    private var availableCurated: [RecommendedMint] {
        let walletUrls = Set(walletMints.map(\.url))
        return RecommendedMint.suggested.filter {
            !existingURLs.contains($0.url) && !walletUrls.contains($0.url)
        }
    }

    var body: some View {
        let hasWallet = !availableWalletMints.isEmpty
        let hasCurated = !availableCurated.isEmpty

        if hasWallet || hasCurated {
            VStack(alignment: .leading, spacing: 0) {
                if hasWallet {
                    sectionHeader("Your mints")
                    ForEach(Array(availableWalletMints.enumerated()), id: \.element.id) { index, mint in
                        mintButton(mint)
                        if index < availableWalletMints.count - 1 || hasCurated {
                            CanvasDivider()
                        }
                    }
                }
                if hasCurated {
                    sectionHeader("Suggested mints")
                        .padding(.top, hasWallet ? 16 : 0)
                    ForEach(Array(availableCurated.enumerated()), id: \.element.id) { index, mint in
                        mintButton(mint)
                        if index < availableCurated.count - 1 {
                            CanvasDivider()
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func mintButton(_ mint: RecommendedMint) -> some View {
        Button {
            onAdd(mint.url)
            HapticFeedback.selection()
        } label: {
            row(for: mint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(mint.name)")
        .accessibilityHint("Stages \(displayHost(mint.url)) for recovery")
    }

    private func row(for mint: RecommendedMint) -> some View {
        HStack(spacing: 12) {
            MintAvatarView(iconUrl: mint.iconUrl, name: mint.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .font(.subheadline.weight(.medium))
                Text(displayHost(mint.url))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func displayHost(_ url: String) -> String {
        var host = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if host.hasSuffix("/") { host = String(host.dropLast()) }
        return host
    }
}

// MARK: - Preview

#Preview("Activity Orb") {
    VStack(spacing: 40) {
        ActivityOrbView(isActive: .constant(true))

        LoadingSpinnerView(message: "Loading wallet...")
    }
}

#Preview("Mutex Lock Overlay") {
    ZStack {
        Text("Main Content")

        MutexLockOverlay(isLocked: .constant(true), message: "Sending tokens...")
    }
}

// MARK: - Mint Logo Cache

/// Process-wide cache for remote mint logos. `AsyncImage` re-issues the network
/// request on every appearance (scrolling a list, opening a sheet, switching
/// tabs) and persists nothing on disk, so logos flicker in and re-download
/// constantly. This keeps decoded images in a bounded in-memory `NSCache` and
/// the raw bytes on disk in the caches directory (keyed by a hash of the URL),
/// so a mint logo downloads once and renders instantly thereafter. Decode and
/// downsampling happen off the main thread. Used via `CachedAsyncImage`.
final class MintLogoCache: @unchecked Sendable {
    static let shared = MintLogoCache()

    /// Upper bound on the decoded thumbnail's longest edge, in pixels. Mint
    /// logos render at most at 72pt (≈216px @3x); 256 keeps them crisp while
    /// capping memory if a mint serves an oversized image.
    private static let maxPixelSize: CGFloat = 256

    /// How long a logo on disk is served before we re-fetch it, so a mint that
    /// swaps its logo is eventually picked up. If the refetch fails (offline),
    /// the stale copy is still used rather than showing nothing.
    private static let ttl: TimeInterval = 7 * 24 * 60 * 60

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 64
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("MintLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Synchronous memory-only lookup, so an already-cached logo renders on the
    /// first frame without a placeholder flash. Nil means "ask `image(for:)`".
    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    /// Returns the logo, loading memory → disk → network as needed. Concurrent
    /// requests for the same URL coalesce onto a single load.
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString
        if let cached = memory.object(forKey: key as NSString) { return cached }

        let task: Task<UIImage?, Never> = {
            lock.lock(); defer { lock.unlock() }
            if let existing = inFlight[key] { return existing }
            let created = Task { await self.load(url: url, key: key) }
            inFlight[key] = created
            return created
        }()

        let image = await task.value
        lock.lock(); inFlight[key] = nil; lock.unlock()
        return image
    }

    private func load(url: URL, key: String) async -> UIImage? {
        let file = directory.appendingPathComponent(Self.filename(for: key))
        let diskData = try? Data(contentsOf: file)

        // Serve an unexpired disk copy without touching the network.
        if let diskData, Self.isFresh(file), let image = await Self.decode(diskData) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }

        // Stale or missing: refetch, but fall back to whatever's on disk — a
        // stale logo beats a blank one when the network is unavailable.
        if let (data, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
           let image = await Self.decode(data) {
            try? data.write(to: file, options: .atomic)
            memory.setObject(image, forKey: key as NSString)
            return image
        }

        if let diskData, let image = await Self.decode(diskData) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        return nil
    }

    /// Wipes every cached logo (memory + disk) and cancels in-flight loads.
    /// Called when the wallet is erased so no per-wallet state lingers.
    func clear() {
        memory.removeAllObjects()
        lock.lock()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func isFresh(_ file: URL) -> Bool {
        guard let modified = try? FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < ttl
    }

    private static func filename(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Decode + downsample off the main thread via ImageIO, so large source
    /// images never get fully decoded into memory.
    private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

// MARK: - Cached Async Image

/// Drop-in replacement for `AsyncImage(url:content:placeholder:)` that loads
/// through `MintLogoCache` instead of refetching on every appearance. The API
/// mirrors `AsyncImage`'s two-closure form: `content` receives the loaded image
/// (success), `placeholder` covers loading and failure. Call sites keep their
/// own `.frame`, `.clipShape`, and fallback styling unchanged.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        // Seed from the memory cache so a previously-loaded logo shows on the
        // first frame, with no placeholder flash.
        _image = State(initialValue: url.flatMap { MintLogoCache.shared.cachedImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = MintLogoCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            image = nil
            image = await MintLogoCache.shared.image(for: url)
        }
    }
}
