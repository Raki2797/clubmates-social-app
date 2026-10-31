import PhotosUI
import SwiftUI
import UIKit

struct AvatarPlaceholder: View {
    let name: String
    let size: CGFloat
    var gradient: LinearGradient = AppTheme.primaryGradient

    var body: some View {
        ZStack {
            gradient
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct ProfilePhotoView: View {
    let photo: ProfilePhoto?
    var symbolName: String = "person.fill"
    var symbolSize: CGFloat = 36
    var gradientColors: [Color] = [AppTheme.surface, AppTheme.surfaceElevated]
    var symbolOpacity: Double = 0.2
    var contentMode: ContentMode = .fill
    var contentAlignment: Alignment = .center
    var contentPadding: CGFloat = 0
    var showsSoftBackdrop: Bool = false

    var body: some View {
        ZStack {
            placeholder(systemName: photo?.systemName ?? symbolName)

            if let data = photo?.imageData, let image = UIImage(data: data) {
                photoImage(image)
            } else if let url = photo?.remoteURL {
                CachedRemoteImage(url: url) { image in
                    photoImage(image)
                } placeholder: {
                    placeholder(systemName: symbolName)
                }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func photoImage(_ image: UIImage) -> some View {
        if contentMode == .fill {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: contentAlignment)
                    .clipped()
            }
        } else {
            ZStack {
                Color.black.opacity(0.86)

                if showsSoftBackdrop {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 28)
                        .scaleEffect(1.12)
                        .opacity(0.42)
                }

                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .padding(contentPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
            }
        }
    }

    private func placeholder(systemName: String) -> some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: systemName)
                .font(.system(size: symbolSize))
                .foregroundColor(.white.opacity(symbolOpacity))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL
    let content: (UIImage) -> Content
    let placeholder: () -> Placeholder

    @State private var downloadedImage: UIImage?

    var body: some View {
        Group {
            if let image = downloadedImage ?? ProfileImageCache.shared.image(for: url) {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImageIfNeeded()
        }
    }

    private func loadImageIfNeeded() async {
        if let cached = ProfileImageCache.shared.image(for: url) {
            downloadedImage = cached
            return
        }

        if let image = await ProfileImageCache.shared.loadImage(for: url) {
            downloadedImage = image
        }
    }
}

@MainActor
final class ProfileImageCache {
    static let shared = ProfileImageCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private var inFlightTasks: [URL: Task<UIImage?, Never>] = [:]
    private let diskQueue = DispatchQueue(label: "com.clubmates.imagecache", qos: .utility)
    private let diskDirectory: URL

    private init() {
        memoryCache.countLimit = 160
        memoryCache.totalCostLimit = 80 * 1024 * 1024

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDirectory = base.appendingPathComponent("ClubMates/photos")
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func loadImage(for url: URL) async -> UIImage? {
        // 1. Memory cache
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        // 2. Disk cache
        if let diskImage = loadFromDisk(url: url) {
            insertMemory(diskImage, for: url)
            return diskImage
        }

        // 3. Deduplicate in-flight downloads
        if let task = inFlightTasks[url] {
            return await task.value
        }

        let task = Task { await Self.downloadImage(from: url) }
        inFlightTasks[url] = task
        let image = await task.value
        inFlightTasks[url] = nil

        if let image {
            insertMemory(image, for: url)
            saveToDisk(image, url: url)
        }
        return image
    }

    func prefetch(urls: [URL]) {
        for url in Set(urls) where image(for: url) == nil && inFlightTasks[url] == nil {
            let task = Task { await Self.downloadImage(from: url) }
            inFlightTasks[url] = task
            Task { [weak self] in
                let image = await task.value
                guard let self else { return }
                self.inFlightTasks[url] = nil
                if let image {
                    self.insertMemory(image, for: url)
                    self.saveToDisk(image, url: url)
                }
            }
        }
    }

    func insertMemory(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    // Called on sign-out — remove all cached photo files
    func clearDisk() {
        diskQueue.async { [diskDirectory] in
            try? FileManager.default.removeItem(at: diskDirectory)
            try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        }
        memoryCache.removeAllObjects()
    }

    // MARK: - Disk helpers

    private func diskURL(for url: URL) -> URL {
        // Use a hash of the URL path (not the full signed URL which changes) as filename.
        // Strip query params so the same photo file reuses the same cache entry.
        let stableKey = url.path
        let hash = stableKey.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        return diskDirectory.appendingPathComponent("\(hash).jpg")
    }

    private func loadFromDisk(url: URL) -> UIImage? {
        let fileURL = diskURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(_ image: UIImage, url: URL) {
        guard let data = image.jpegData(compressionQuality: 1.0) else { return }
        let fileURL = diskURL(for: url)
        diskQueue.async {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func downloadImage(from url: URL) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

struct ProfileAvatar: View {
    let profile: UserProfile
    let size: CGFloat
    var gradient: LinearGradient = AppTheme.primaryGradient

    var body: some View {
        Group {
            if let data = profile.mainPhoto?.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = profile.mainPhoto?.remoteURL {
                CachedRemoteImage(url: url) { image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    AvatarPlaceholder(name: profile.name, size: size, gradient: gradient)
                }
            } else {
                AvatarPlaceholder(name: profile.name, size: size, gradient: gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct PhotoLibraryPickerButton<Label: View>: View {
    let maxSelectionCount: Int
    let onPhotosPicked: ([ProfilePhoto]) -> Void
    let label: () -> Label

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var showLoadError = false
    @State private var pendingImages: [UIImage] = []
    @State private var showCrop = false

    // Single-photo convenience init (replace flow)
    init(
        onPhotoPicked: @escaping (ProfilePhoto) -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.maxSelectionCount = 1
        self.onPhotosPicked = { photos in photos.first.map { onPhotoPicked($0) } }
        self.label = label
    }

    // Multi-select init (add flow)
    init(
        maxSelectionCount: Int,
        onPhotosPicked: @escaping ([ProfilePhoto]) -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.maxSelectionCount = maxSelectionCount
        self.onPhotosPicked = onPhotosPicked
        self.label = label
    }

    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: maxSelectionCount,
            matching: .images
        ) {
            ZStack {
                label()
                if isLoading {
                    Color.black.opacity(0.24)
                    ProgressView().tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadImages(from: newItems) }
        }
        .fullScreenCover(isPresented: $showCrop, onDismiss: { pendingImages = [] }) {
            PhotoCropView(
                images: pendingImages,
                onComplete: { croppedDataList in
                    let photos = croppedDataList.map { ProfilePhoto(imageData: $0) }
                    showCrop = false
                    onPhotosPicked(photos)
                },
                onCancel: {
                    showCrop = false
                }
            )
        }
        .alert("Couldn't load photo", isPresented: $showLoadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please choose a different image and try again.")
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        await MainActor.run { isLoading = true }
        defer {
            Task { @MainActor in
                isLoading = false
                selectedItems = []
            }
        }

        var loaded: [UIImage] = []
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            } catch {
                // skip individual failed items
            }
        }

        if loaded.isEmpty {
            await MainActor.run { showLoadError = true }
            return
        }

        await MainActor.run {
            pendingImages = loaded
            showCrop = true
        }
    }
}
