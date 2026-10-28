import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// File-format normalization only: preserve dimensions/UI, remove the PNG alpha channel.
// Original simulator/window captures are never modified.
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Usage: normalize-screenshots raw-directory new-output-directory") }
let source = URL(fileURLWithPath: arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let manager = FileManager.default
if manager.fileExists(atPath: output.path) { fatalError("Refusing to overwrite an existing output directory") }
try manager.createDirectory(at: output, withIntermediateDirectories: true)
for family in ["iphone", "iphone-max", "ipad", "mac"] {
    let folder = source.appendingPathComponent(family, isDirectory: true)
    guard manager.fileExists(atPath: folder.path) else { continue }
    let destination = output.appendingPathComponent(family, isDirectory: true)
    try manager.createDirectory(at: destination, withIntermediateDirectories: true)
    for file in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) where file.pathExtension.lowercased() == "png" {
        guard let reader = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(reader, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            fatalError("Cannot decode capture \(file.lastPathComponent)")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let opaque = context.makeImage(),
              let writer = CGImageDestinationCreateWithURL(destination.appendingPathComponent(file.lastPathComponent) as CFURL,
                                                          UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Cannot export capture")
        }
        CGImageDestinationAddImage(writer, opaque, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { fatalError("Cannot save capture") }
        print("Exported \(family)/\(file.lastPathComponent) \(image.width)x\(image.height), opaque PNG")
    }
}
