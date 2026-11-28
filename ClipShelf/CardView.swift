import AppKit
import ImageIO
import SwiftUI

struct CardView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool

    static let size = CGSize(width: 230, height: 230)
    static let cornerRadius: CGFloat = 12
    static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.85), in: Self.shape)
        .overlay(
            Self.shape
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.25 : 0.1), radius: isSelected ? 8 : 3, y: 2)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.easeOut(duration: 0.1), value: isSelected)
    }

    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                if let title = item.title {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    (Text(kindTitle + " · ") + Text(item.lastUsedAt, format: .relative(presentation: .named)))
                        .font(.caption2)
                        .lineLimit(1)
                        .opacity(0.85)
                } else {
                    Text(kindTitle).font(.subheadline.weight(.semibold))
                    Text(item.lastUsedAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .opacity(0.85)
                }
            }
            Spacer(minLength: 0)
            if let icon = AppIconCache.icon(for: item.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                    .help(item.sourceAppName ?? "")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Shaped here instead of clipping the whole card: a card cut off by the edge of the scroll view
        // got the clip's rounded corners on the header's bottom edge too.
        .background(kindColor.gradient, in: UnevenRoundedRectangle(
            topLeadingRadius: Self.cornerRadius, topTrailingRadius: Self.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let thumbnail = ThumbnailCache.thumbnail(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        case .file:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.fileURLs.prefix(4), id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                        Text(url.lastPathComponent).lineLimit(2).font(.callout)
                    }
                }
                if item.fileURLs.count > 4 {
                    Text("+\(item.fileURLs.count - 4) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link").font(.title2).foregroundStyle(kindColor)
                Text(item.text ?? "").font(.callout).lineLimit(6).foregroundStyle(.primary)
            }
        case .text, .richText:
            Text(previewText)
                .font(item.isCode ? .system(size: 11, design: .monospaced) : .system(size: 12.5))
                .lineLimit(item.isCode ? 12 : 9)
                .foregroundStyle(.primary)
        }
    }

    private var footer: some View {
        HStack {
            Text(detailText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
    }

    private var previewText: String {
        let text = item.text ?? ""
        return text.count > 1500 ? String(text.prefix(1500)) : text
    }

    private var kindTitle: String {
        if let language = item.codeLanguage { return CodeDetector.displayName(of: language) }
        switch item.kind {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .link: return "Link"
        case .image: return "Image"
        case .file: return item.fileURLs.count == 1 ? "File" : "\(item.fileURLs.count) Files"
        }
    }

    private var kindColor: Color {
        if item.isCode { return .indigo }
        switch item.kind {
        case .text: return .blue
        case .richText: return .teal
        case .link: return .orange
        case .image: return .pink
        case .file: return .green
        }
    }

    private var detailText: String {
        switch item.kind {
        case .image:
            if let size = ThumbnailCache.pixelSize(for: item) { return "\(Int(size.width)) × \(Int(size.height))" }
            return ""
        case .file:
            return item.fileURLs.first?.deletingLastPathComponent().path ?? ""
        default:
            let count = item.text?.count ?? 0
            return "\(count) characters"
        }
    }
}

enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

enum ThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static var sizes: [UUID: CGSize] = [:]

    static func thumbnail(for item: ClipItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = item.imageData, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 440,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    static func pixelSize(for item: ClipItem) -> CGSize? {
        if let size = sizes[item.id] { return size }
        guard let data = item.imageData, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let size = CGSize(width: width, height: height)
        sizes[item.id] = size
        return size
    }
}
