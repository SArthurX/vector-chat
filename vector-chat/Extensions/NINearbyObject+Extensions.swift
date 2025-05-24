//
//  NINearbyObject+Extensions.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import NearbyInteraction

// MARK: - NINearbyObject.RemovalReason 的描述擴展
extension NINearbyObject.RemovalReason {
    var description: String {
        switch self {
        case .timeout:
            return "Timeout"
        case .peerEnded:
            return "Peer Ended"
        @unknown default:
            return "Unknown"
        }
    }
}
