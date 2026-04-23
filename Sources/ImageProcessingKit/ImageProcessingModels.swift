//
//  ImageProcessingModels.swift
//  ImageProcessingKit
//
//  Created by Dustin Nielson on 2/7/26.
//

import Foundation
import CoreVideo

#if os(macOS)
import AppKit
/// Platform-agnostic image type — NSImage on macOS, UIImage on iOS/tvOS
public typealias PlatformImage = NSImage
#else
import UIKit
/// Platform-agnostic image type — NSImage on macOS, UIImage on iOS/tvOS
public typealias PlatformImage = UIImage
#endif

// MARK: - Errors

/// Errors specific to image loading and pixel buffer conversion
public enum ImageProcessingError: Error, Sendable {
    /// The specified file URL does not exist or is not readable
    case fileNotFound(URL)
    /// The image format is not supported (PNG, JPEG, WebP are supported)
    case unsupportedFormat(String)
    /// The image data could not be decoded into a platform image
    case decodingFailed
    /// CVPixelBuffer creation failed during conversion
    case pixelBufferCreationFailed
    /// The image has zero or negative dimensions
    case invalidImageDimensions
}

// MARK: - Delegate Protocol

/// Optional delegate for receiving async image loading events.
///
/// While `ImageProcessor` primarily provides synchronous APIs for the render pipeline,
/// the delegate enables notification-based patterns for background image loading workflows.
public protocol ImageProcessorDelegate: AnyObject {
    /// Called when an image has been successfully loaded
    /// - Parameters:
    ///   - processor: The image processor that loaded the image
    ///   - image: The loaded platform image
    ///   - identifier: The processor's identifier
    func imageProcessor(_ processor: ImageProcessor, didLoadImage image: PlatformImage, for identifier: String)

    /// Called when an image failed to load
    /// - Parameters:
    ///   - processor: The image processor that encountered the error
    ///   - identifier: The processor's identifier
    ///   - error: The error that occurred
    func imageProcessor(_ processor: ImageProcessor, didFailToLoadImage identifier: String, error: ImageProcessingError)
    func imageProcessorDurationTimerComplete(identifier: String)
}

/// Default implementations — all delegate methods are optional
public extension ImageProcessorDelegate {
    func imageProcessor(_ processor: ImageProcessor, didLoadImage image: PlatformImage, for identifier: String) {}
    func imageProcessor(_ processor: ImageProcessor, didFailToLoadImage identifier: String, error: ImageProcessingError) {}
    func imageProcessorDurationTimerComplete(identifier: String) {}
}
