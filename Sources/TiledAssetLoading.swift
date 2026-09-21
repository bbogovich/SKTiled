//
//  TiledAssetLoading.swift
//  SKTiled
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import ImageIO
import SpriteKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


/// Resolves `source` attributes the way Tiled does, with fallbacks for bundles whose folder structure was flattened.
///
/// Tiled writes every `source` relative to the file that contains it. That is tried first. When the file is not
/// there (typically because the assets were added to Xcode as a group, which copies them into one folder), the
/// file name is looked up in the directory of the file that was loaded first, and then in the bundle.
internal struct TiledAssetResolver {

    /// Directory of the file passed to the loader.
    let rootDirectory: URL

    /// Bundle searched by file name when relative resolution fails.
    let bundle: Bundle?

    /// Returns the URL of an existing file for `source`, or `nil`.
    ///
    /// - Parameters:
    ///   - source: `source` attribute value.
    ///   - file: file containing the attribute.
    func url(for source: String, referencedBy file: URL) -> URL? {
        let fileManager = FileManager.default
        let relative = URL(fileURLWithPath: source, relativeTo: file.deletingLastPathComponent()).standardizedFileURL
        if fileManager.fileExists(atPath: relative.path) {
            return relative
        }

        let filename = relative.lastPathComponent
        let flattened = rootDirectory.appendingPathComponent(filename).standardizedFileURL
        if fileManager.fileExists(atPath: flattened.path) {
            return flattened
        }

        let ext = relative.pathExtension
        let name = relative.deletingPathExtension().lastPathComponent
        return bundle?.url(forResource: name, withExtension: ext.isEmpty ? nil : ext)?.standardizedFileURL
    }
}


/// Decodes images referenced by Tiled files.
internal enum TiledImageLoader {

    /// Decodes an image file in any format ImageIO supports.
    static func cgImage(contentsOf url: URL) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TiledError.fileNotFound(url, referencedBy: nil)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
            throw TiledError.unsupportedImage(url)
        }
        return image
    }

    /// Looks up an image in a bundle's asset catalog (or loose bundle images) by name.
    static func cgImage(named name: String, in bundle: Bundle) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(named: name, in: bundle, with: nil)?.cgImage
        #elseif canImport(AppKit)
        var rect = CGRect.zero
        return bundle.image(forResource: name)?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    /// Returns the image for a `source` attribute, trying the file system first and then the asset catalog.
    ///
    /// - Parameters:
    ///   - source: `source` attribute value.
    ///   - file: file containing the attribute.
    ///   - resolver: resolver for the current load.
    /// - Returns: decoded image and the file it came from (`nil` for asset catalog images).
    static func image(for source: String,
                      referencedBy file: URL,
                      resolver: TiledAssetResolver) throws -> (image: CGImage, url: URL?) {
        if let url = resolver.url(for: source, referencedBy: file) {
            return (try cgImage(contentsOf: url), url)
        }
        let name = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        if let bundle = resolver.bundle, let image = cgImage(named: name, in: bundle) {
            return (image, nil)
        }
        throw TiledError.imageNotFound(source: source, referencedBy: file)
    }

    /// Creates a pixel-art texture from an image.
    static func texture(from image: CGImage) -> SKTexture {
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }
}


extension Bundle {

    /// Finds a Tiled file by name.
    ///
    /// `name` may include the extension and a relative path. Without a `subdirectory`, the whole resource
    /// directory is searched, shallowest match first.
    internal func tiledResourceURL(named name: String, extension ext: String, subdirectory: String?) -> URL? {
        let requested = name as NSString
        let basename = requested.lastPathComponent
        let filename = (basename as NSString).pathExtension.lowercased() == ext ? basename : basename + "." + ext
        let directory = [subdirectory ?? "", requested.deletingLastPathComponent]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard let resourceURL = resourceURL else { return nil }
        let searchRoot = directory.isEmpty ? resourceURL : resourceURL.appendingPathComponent(directory)

        let direct = searchRoot.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct.standardizedFileURL
        }
        guard subdirectory == nil else { return nil }

        let matches = FileManager.default.enumerator(at: searchRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == filename } ?? []
        return matches.min { $0.pathComponents.count < $1.pathComponents.count }?.standardizedFileURL
    }
}
