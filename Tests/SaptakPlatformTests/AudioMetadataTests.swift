import XCTest
import AVFoundation
import MediaPlayer
import ImageIO
import UniformTypeIdentifiers
import SaptakCore
@testable import SaptakPlatform

final class AudioMetadataTests: XCTestCase {
    func testEmptyAndOversizedTextIsNormalized() {
        let value = AudioMetadata(title: " \n ", artist: "Artist\nName", album: String(repeating: "a", count: 900))
        XCTAssertNil(value.title)
        XCTAssertEqual(value.artist, "Artist Name")
        XCTAssertEqual(value.album?.count, 512)
    }

    func testEmbeddedCommonMetadataIsReadWithoutChangingItems() async {
        func item(_ identifier: AVMetadataIdentifier, _ text: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = text as NSString
            return item
        }
        let items = [item(.commonIdentifierTitle, "Song"), item(.commonIdentifierArtist, "Singer"), item(.commonIdentifierAlbumName, "Album")]
        let value = await AudioMetadata.load(items: items)
        XCTAssertEqual(value.title, "Song")
        XCTAssertEqual(value.artist, "Singer")
        XCTAssertEqual(value.album, "Album")
        XCTAssertNil(value.artwork)
        let empty = await AudioMetadata.load(items: [])
        XCTAssertEqual(empty, AudioMetadata())
    }

    func testInvalidAndExcessiveArtworkIsIgnored() {
        XCTAssertNil(AudioMetadata.thumbnail(Data([0, 1, 2])))
        XCTAssertNil(AudioMetadata.thumbnail(Data(repeating: 0, count: 5 * 1024 * 1024 + 1)))
    }

    func testArtworkThumbnailIsBoundedAndDecodable() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let thumbnail = try XCTUnwrap(AudioMetadata.thumbnail(data as Data))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(decoded.width, 512)
        XCTAssertLessThanOrEqual(decoded.height, 512)
    }

    @MainActor func testTitleFallbackAndStaleTrackMetadataCannotReplaceSelection() {
        let player = PlayerModel()
        defer { player.stop() }
        let first = AudioTrack(url: URL(fileURLWithPath: "/library/first.m4a"))
        let next = AudioTrack(url: URL(fileURLWithPath: "/library/next.m4a"))
        player.play([first, next], access: nil)
        XCTAssertEqual(player.title, "first")
        player.applyMetadata(AudioMetadata(title: "Tagged", artist: "Artist", album: "Album"), for: first)
        XCTAssertEqual(player.title, "Tagged")
        XCTAssertEqual(player.subtitle, "Artist · Album")
        player.next()
        player.applyMetadata(AudioMetadata(title: "Stale"), for: first)
        XCTAssertEqual(player.title, "next")
        XCTAssertEqual(player.subtitle, "library")
    }

    func testSystemMetadataUsesEmbeddedTagsWithoutFileLocations() throws {
        let state = SystemPlaybackState(title: "Song", index: 0, count: 1, position: 5, duration: 90,
                                        isPlaying: true, isLoading: false, canGoNext: false,
                                        artist: "Singer", album: "Album")
        let info = try XCTUnwrap(state.metadata)
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "Singer")
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, "Album")
        XCTAssertNil(info[MPMediaItemPropertyAssetURL])
    }
}
