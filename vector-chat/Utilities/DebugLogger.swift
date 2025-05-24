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
    let fileName = (file as NSString).lastPathComponent
    print("[\(fileName):\(line)] \(function): \(message)")
    #endif
}
