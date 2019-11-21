//
//  BleLogger.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

@objc public enum BleLogSeverity: Int {
    case trace
    case debug
    case info
    case warn
    case error
}

@objc public protocol BleLoggerHandler {
    func insertLog(_ log: String, _ severity: BleLogSeverity)
}

@objc public class BleLogger : NSObject {
    
    @objc public static var logSeverity = BleLogSeverity.debug
    @objc public static var loggerHandler: BleLoggerHandler? = nil
    
    private static let severityString: [BleLogSeverity:String] = [.trace:"TRACE", .debug:"DEBUG", .info:"INFO", .warn:"WARN", .error:"ERROR"]
    
    @objc public static func trace(_ content: @autoclosure () -> String) {
        insertLog(content(), .trace)
    }
    
    @objc public static func debug(_ content: @autoclosure () -> String) {
        insertLog(content(), .debug)
    }
    
    @objc public static func info(_ content: @autoclosure () -> String) {
        insertLog(content(), .info)
    }
    
    @objc public static func warn(_ content: @autoclosure () -> String) {
        insertLog(content(), .warn)
    }
    
    @objc public static func error(_ content: @autoclosure () -> String) {
        insertLog(content(), .error)
    }
    
    private static func insertLog(_ content: @autoclosure () -> String, _ severity: BleLogSeverity) {
        guard severity.rawValue >= logSeverity.rawValue else {
            return
        }
        let log = content()
        guard loggerHandler == nil else {
            loggerHandler!.insertLog(log, severity)
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        print("\(formatter.string(from: Date())) [\(severityString[severity]!)] \(log)")
    }
}

extension Data {
    var hexString: String {
        return "\(self.map{ String(format: "%02x", $0) }.joined(separator: " ")) (\(self.count) bytes)"
    }
}
