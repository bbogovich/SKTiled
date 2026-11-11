//
//  SKImageLayer.swift
//  SKTiled
//
//  Created by Michael Fessenden.
//
//  Web: https://github.com/mfessenden
//  Email: michael.fessenden@gmail.com
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

import SpriteKit
import GameplayKit
#if os(iOS) || os(tvOS)
import UIKit
#else
import Cocoa
#endif


/// ## Overview
///
/// The `SKImageLayer` object is really nothing more than a sprite with positioning attributes.
///
/// ### Properties
///
/// | Property | Description        |
/// |:---------|:-------------------|
/// | image    | Layer image name.  |
/// | wrapX    | Wrap horizontally. |
/// | wrapY    | Wrap vertically.   |
///
///
/// ### Methods ###
///
/// | Method          | Description              |
/// |:----------------|:-------------------------|
/// | setLayerImage   | Set the layer's image.   |
/// | setLayerTexture | Set the layer's texture. |
/// | wrapY           | Wrap vertically.         |
///
/// ### Usage
///
/// Set the layer image with:
///
/// ```swift
/// try imageLayer.setLayerImage(url: cloudsURL)
/// ```
public class SKImageLayer: SKTiledLayerObject {
    
    public var image: String?                       // image path or name for layer
    private var textures: [SKTexture] = []          // texture values
    private var sprite: SKSpriteNode?               // sprite
    
    public var wrapX: Bool = false                  // wrap horizontally
    public var wrapY: Bool = false                  // wrap vertically
    
    // MARK: - Init
    
    /// Initialize with a layer name, and parent `SKTilemap` node.
    ///
    /// - parameter layerName: `String` image layer name.
    /// - parameter tilemap:   `SKTilemap` parent map.
    override public init(layerName: String, tilemap: SKTilemap) {
        super.init(layerName: layerName, tilemap: tilemap)
        self.layerType = .image
    }
    
    /// Initialize with parent `SKTilemap` and layer attributes.
    ///
    /// **Do not use this intializer directly**
    ///
    /// - parameter tilemap:      `SKTilemap` parent map.
    /// - parameter attributes:   `[String: String]` layer attributes.
    public init?(tilemap: SKTilemap, attributes: [String: String]) {
        guard let layerName = attributes["name"] else { return nil }
        super.init(layerName: layerName, tilemap: tilemap, attributes: attributes)
        self.layerType = .image
    }
    
    /// Sets the layer image from an image file.
    ///
    /// - Parameter url: image file (any format ImageIO can decode).
    /// - Throws: `TiledError` if the image cannot be read.
    public func setLayerImage(url: URL) throws {
        let image = try TiledImageLoader.cgImage(contentsOf: url)
        setLayerImage(image, source: url.path)
    }

    /// Sets the layer image from a decoded image.
    ///
    /// - Parameters:
    ///   - image: layer image.
    ///   - source: image path or name, recorded as the layer's `image`.
    public func setLayerImage(_ image: CGImage, source: String) {
        self.image = source

        let texture = TiledImageLoader.texture(from: image)
        textures.append(texture)
        let textureSize = texture.size()

        let sprite = SKSpriteNode(texture: texture)
        sprite.position.x += textureSize.width / 2
        sprite.position.y -= textureSize.height / 2
        self.sprite?.removeFromParent()
        self.sprite = sprite
        addChild(sprite)
    }

    /// Replaces the layer sprite with a texture.
    ///
    /// - Parameter texture: layer image texture.
    public func setLayerTexture(texture: SKTexture) {
        self.sprite?.removeFromParent()
        let sprite = SKSpriteNode(texture: texture)
        self.sprite = sprite
        addChild(sprite)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Updating: Image Layer
    
    /// Update the image layer before each frame is rendered.
    ///
    /// - parameter currentTime: `TimeInterval` update interval.
    override public func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
    }
}
