//
//  ImageProcessor.swift
//  ImageProcessingKit
//
//  Created by Dustin Nielson on 2/7/26.
//
//  Loads image files and converts them to CVPixelBuffer for the Metal rendering pipeline.
//  Parallel to VideoPlayerKit (video → buffer) and CaptureKit (capture → buffer).
//
//  All CVPixelBuffer output uses kCVPixelFormatType_32BGRA with Metal compatibility flags,
//  matching the format produced by VideoPlayerKit and CaptureKit.
//

import Foundation
import CoreVideo
import CoreGraphics
import ImageIO
import OSLog
import LoggingKit


#if os(macOS)
import AppKit
#else
import UIKit
#endif


// MARK: - Format Support

/// Supported image MIME types for the platform
public let supportedImageTypes: Set<String> = [
    "image/png",
    "image/jpeg",
    "image/webp"
]

/// WebP is natively supported on all target platforms (iOS 14+, macOS 11+, tvOS 14+)
@inline(__always)
public var isWebPSupported: Bool { true }

// MARK: - ImageProcessor

/// Loads image files and converts them to CVPixelBuffer for the Metal rendering pipeline.
///
/// `ImageProcessor` provides the image buffer source for the consumer client's three-source
/// architecture, alongside `VideoPlayerKit` (video frames) and `CaptureKit` (capture frames).
///
/// All CVPixelBuffer output uses `kCVPixelFormatType_32BGRA` with Metal compatibility flags,
/// matching the pixel format produced by the other two kits.
///
/// Usage:
/// ```swift
/// let processor = ImageProcessor(identifier: "zone-main")
/// let buffer = try processor.pixelBuffer(from: imageFileURL)
/// // buffer is ready for Metal texture conversion or compositor input
/// ```
public final class ImageProcessor: @unchecked Sendable {
    
    /// Timer for image duration rotation
    var rotationTimer: Timer?

    /// Duration each image is displayed before advancing (seconds)
    let imageDuration: TimeInterval = 8.0
    
   /// Unique identifier for this processor instance (matches zone or content identifier)
    public let identifier: String

    /// Optional delegate for async loading events
    public weak var delegate: ImageProcessorDelegate?

    /// Create an image processor with a unique identifier
    /// - Parameter identifier: Unique identifier, typically matching a zone or content item ID
    public init(identifier: String) {
        self.identifier = identifier
    }

    // MARK: - Image Loading

    /// Load an image from a local file URL
    /// - Parameter url: Local file URL to an image (PNG, JPEG, or WebP)
    /// - Returns: The loaded platform image
    /// - Throws: `ImageProcessingError.fileNotFound` if the file doesn't exist,
    ///           `ImageProcessingError.decodingFailed` if the image can't be decoded
    public func loadImage(from url: URL, imageDuration: TimeInterval = 8.0) throws -> PlatformImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let error = ImageProcessingError.fileNotFound(url)
            delegate?.imageProcessor(self, didFailToLoadImage: identifier, error: error)
            throw error
        }
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else {
            let error = ImageProcessingError.decodingFailed
            delegate?.imageProcessor(self, didFailToLoadImage: identifier, error: error)
            throw error
        }
        #else
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            let error = ImageProcessingError.decodingFailed
            delegate?.imageProcessor(self, didFailToLoadImage: identifier, error: error)
            throw error
        }
        #endif

        delegate?.imageProcessor(self, didLoadImage: image, for: identifier)
        
        return image
    }

    /// Load a WebP image from raw data
    /// - Parameter data: Raw WebP image data
    /// - Returns: The decoded platform image
    /// - Throws: `ImageProcessingError.decodingFailed` if WebP decoding fails
    public func loadWebP(from data: Data) throws -> PlatformImage {
        // Native ImageIO support handles WebP automatically on our target platforms
        #if os(macOS)
        guard let image = NSImage(data: data) else {
            let error = ImageProcessingError.decodingFailed
            delegate?.imageProcessor(self, didFailToLoadImage: identifier, error: error)
            throw error
        }
        #else
        guard let image = UIImage(data: data) else {
            let error = ImageProcessingError.decodingFailed
            delegate?.imageProcessor(self, didFailToLoadImage: identifier, error: error)
            throw error
        }
        #endif

        delegate?.imageProcessor(self, didLoadImage: image, for: identifier)
        return image
    }

    // MARK: - Buffer Conversion

    /// Convert a platform image to a CVPixelBuffer suitable for the Metal pipeline.
    ///
    /// This is the primary pipeline method — analogous to `VideoPlayer.directBufferCheck()`.
    /// Output format is `kCVPixelFormatType_32BGRA` with Metal compatibility flags.
    ///
    /// - Parameter image: The platform image to convert
    /// - Returns: A Metal-compatible CVPixelBuffer, or nil if conversion fails
    public func pixelBuffer(from image: PlatformImage, imageDuration: TimeInterval = 8.0) -> CVPixelBuffer? {
        if imageDuration > 0 {
            scheduleRotationTimer(duration: imageDuration)
        }
        
        #if os(macOS)
        return macOSPixelBuffer(from: image)
        #else
        return iOSPixelBuffer(from: image)
        #endif
    }

    /// Load a file and convert to CVPixelBuffer in one step.
    ///
    /// Convenience that combines `loadImage(from:)` and `pixelBuffer(from:)`.
    ///
    /// - Parameter url: Local file URL to an image
    /// - Returns: A Metal-compatible CVPixelBuffer, or nil if conversion fails
    /// - Throws: `ImageProcessingError` if the file can't be loaded
    public func pixelBuffer(from url: URL) throws -> CVPixelBuffer? {
        let image = try loadImage(from: url)
        return pixelBuffer(from: image)
    }

    // MARK: - Rotation Timer

    /// Schedule the image duration timer on the main RunLoop.
    ///
    /// `Timer.scheduledTimer` adds the timer to the *current thread's* RunLoop.
    /// When `pixelBuffer(from:)` is called from a background thread (e.g., an
    /// AVFoundation callback or MarqueeKit delegate), the background RunLoop is
    /// typically not active, so the timer never fires. Dispatching to main
    /// guarantees the timer is added to the main RunLoop and will fire reliably.
    private func scheduleRotationTimer(duration: TimeInterval) {
        let work = { [weak self] in
            self?.rotationTimer?.invalidate()
            self?.rotationTimer = nil
            self?.rotationTimer = Timer.scheduledTimer(
                withTimeInterval: duration,
                repeats: false
            ) { [weak self] _ in
                self?.delegate?.imageProcessorDurationTimerComplete(identifier: self?.identifier ?? "")
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Cancel any active rotation timer.
    public func cancelRotationTimer() {
        let work = { [weak self] in
            self?.rotationTimer?.invalidate()
            self?.rotationTimer = nil
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - Platform-Specific Pixel Buffer Creation

    #if os(macOS)
    private func macOSPixelBuffer(from image: NSImage) -> CVPixelBuffer? {
        let width = image.size.width
        let height = image.size.height

        guard width > 0 && height > 0 else {
            mlog.error("Invalid image dimensions: \(width)x\(height)")
            return nil
        }

        let attrs = [
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(width),
            Int(height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )

        guard let resultPixelBuffer = pixelBuffer, status == kCVReturnSuccess else {
            mlog.error("CVPixelBufferCreate failed with status: \(status)")
            return nil
        }

        CVPixelBufferLockBaseAddress(resultPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(resultPixelBuffer)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pixelData,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(resultPixelBuffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(resultPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            mlog.error("Failed to create CGContext for macOS image")
            return nil
        }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        CVPixelBufferUnlockBaseAddress(resultPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return resultPixelBuffer
    }
    #else
    private func iOSPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let size = image.size

        guard size.width > 0 && size.height > 0 else {
            mlog.error("Invalid image size: \(size.width)x\(size.height)")
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)

        guard let cgImage = renderer.image(actions: { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }).cgImage else {
            mlog.error("Failed to create CGImage from UIImage")
            return nil
        }

        let options: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            mlog.error("CVPixelBufferCreate failed with status: \(status)")
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            mlog.error("Failed to create CGContext for iOS image")
            return nil
        }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        return pixelBuffer
    }
    #endif
}
