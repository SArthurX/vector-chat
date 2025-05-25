//
//  DebugLogger.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import Foundation

/// 調試日誌工具
public func debuglog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let timestamp = formatter.string(from: Date())

    let fileName = (file as NSString).lastPathComponent
    // print("[\(fileName):\(line)] \(function): \(message)")

    print("\(timestamp) >>> \(message)")
    #endif
}



