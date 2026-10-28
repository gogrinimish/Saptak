import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct AudioMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: Data?

    init(title: String? = nil, artist: String? = nil, album: String? = nil, artwork: Data? = nil) {
        func clean(_ value: String?) -> String? {
            guard let text = value?.components(separatedBy: .controlCharacters).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return String(text.prefix(512))
        }
        self.title = clean(title)
        self.artist = clean(artist)
        self.album = clean(album)
        self.artwork = artwork
    }

    static func load(from asset: AVAsset) async -> AudioMetadata {
        guard let items = try? await asset.load(.commonMetadata) else { return AudioMetadata() }
        return await load(items: items)
    }

    static func load(items: [AVMetadataItem]) async -> AudioMetadata {
        func text(_ identifier: AVMetadataIdentifier) async -> String? {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            }
            return nil
        }
        let title = await text(.commonIdentifierTitle)
        let artist = await text(.commonIdentifierArtist)
        let album = await text(.commonIdentifierAlbumName)
        var artwork: Data?
        if !Task.isCancelled {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork) {
                if let data = try? await item.load(.dataValue), let thumbnail = await Task.detached(priority: .utility, operation: { thumbnail(data) }).value {
                    artwork = thumbnail
                    break
                }
            }
        }
        return AudioMetadata(title: title, artist: artist, album: album, artwork: artwork)
    }

    static func thumbnail(_ data: Data) -> Data? {
        guard data.count <= 5 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
