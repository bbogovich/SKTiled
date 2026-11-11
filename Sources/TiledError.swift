//
//  TiledError.swift
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


/// Errors thrown while loading Tiled maps, tilesets, templates and images.
public enum TiledError: Error, Equatable, Sendable {

    /// A map or tileset could not be found by name in a bundle.
    case resourceNotFound(name: String, bundle: URL)

    /// A file does not exist. `referencedBy` is the file whose `source` attribute named it, if any.
    case fileNotFound(URL, referencedBy: URL?)

    /// A file exists but could not be read.
    case unreadableFile(URL, reason: String)

    /// A file is not well-formed XML.
    case invalidXML(URL, line: Int, column: Int, reason: String)

    /// A file is well-formed but does not describe valid Tiled content.
    case invalidContent(URL, reason: String)

    /// An image `source` could not be found on disk or in the bundle's asset catalog.
    case imageNotFound(source: String, referencedBy: URL)

    /// An image file exists but could not be decoded.
    case unsupportedImage(URL)

    /// The file uses a Tiled feature SKTiled does not implement.
    case unsupportedFeature(URL, feature: String)
}


extension TiledError: LocalizedError {

    public var errorDescription: String? {
        switch self {
            case let .resourceNotFound(name, bundle):
                return "\"\(name)\" was not found in bundle \"\(bundle.lastPathComponent)\"."
            case let .fileNotFound(url, referencedBy):
                if let referencedBy = referencedBy {
                    return "\"\(url.path)\" (referenced by \"\(referencedBy.lastPathComponent)\") does not exist."
                }
                return "\"\(url.path)\" does not exist."
            case let .unreadableFile(url, reason):
                return "\"\(url.lastPathComponent)\" could not be read: \(reason)"
            case let .invalidXML(url, line, column, reason):
                return "\"\(url.lastPathComponent)\" line \(line), column \(column): \(reason)"
            case let .invalidContent(url, reason):
                return "\"\(url.lastPathComponent)\": \(reason)"
            case let .imageNotFound(source, referencedBy):
                return "image \"\(source)\" (referenced by \"\(referencedBy.lastPathComponent)\") was not found."
            case let .unsupportedImage(url):
                return "\"\(url.lastPathComponent)\" is not a supported image."
            case let .unsupportedFeature(url, feature):
                return "\"\(url.lastPathComponent)\": \(feature) is not supported."
        }
    }
}
