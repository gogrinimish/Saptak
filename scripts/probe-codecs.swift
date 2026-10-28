// Compile with: swiftc -parse-as-library scripts/probe-codecs.swift -o /tmp/saptak-codecs
// Run with paths to nonpersonal sample recordings. No files are modified.
import Foundation
import AVFoundation

@main struct CodecProbe {
    static func main() async {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: saptak-codecs <recording> [recording …]")
            return
        }
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            do {
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration)
                print("\(url.lastPathComponent): playable=\(playable), duration=\(duration.seconds)")
            } catch {
                print("\(url.lastPathComponent): FAILED \(error)")
            }
        }
    }
}
