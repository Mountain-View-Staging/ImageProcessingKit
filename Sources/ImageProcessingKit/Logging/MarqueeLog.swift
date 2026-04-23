//
//  MarqueeLog.swift
//  ImageProcessingKit
//
import OSLog
import LoggingKit

// MARK: - Module-level instance

let mlog = MarqueeLog(
    logger: Logger(subsystem: "com.mvsmarquee.ImageProcessingKit", category: "ImageProcessingKit"),
    projectTag: "ImageProcessingKit"
)
