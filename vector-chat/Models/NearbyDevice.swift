//
//  NearbyDevice.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import SwiftUI
import MultipeerConnectivity
import simd

/// 表示一個被偵測到的附近裝置
struct NearbyDevice: Identifiable, Equatable {
    let id: MCPeerID // 使用 MCPeerID 作為唯一標識符
    var displayName: String // 裝置的顯示名稱
    var distance: Float? // 距離（公尺）
    var direction: simd_float3? // 方向向量
    var lastUpdateTime: Date = Date() // 最後更新時間，用於清理長時間未更新的裝置

    /// 為了在視圖中定位，計算相對於中心點的 CGPoint
    var position: CGPoint? {
        guard let distance = distance, let direction = direction else { return nil }
        
        // 假設方向向量的 x 和 z 分量對應到 2D 平面的 x 和 y
        // 這裡的轉換比例需要根據您的地圖視圖大小進行調整
        let scaleFactor: Float = 50.0 // 1 公尺對應 50 個點
        
        // UWB 的方向通常是 (x, y, z)，在地圖上我們可能用 x 和 z (或 x 和 y，取決於座標系統定義)
        // 這裡假設 direction.x 是橫向，direction.z 是縱向 (前方)
        // 注意：UWB 的方向向量是相對於本機裝置的。
        // 如果 direction.z 是正數，表示在前方；負數表示在後方。
        // 如果 direction.x 是正數，表示在右方；負數表示在左方。
        // 在 SwiftUI 座標中，y 軸向下為正。因此，如果 direction.z 為正 (前方)，在地圖上應該是向上 (y 負方向)。
        return CGPoint(
            x: CGFloat(direction.x * distance * scaleFactor),
            y: CGFloat(direction.z * distance * scaleFactor) // y 軸反轉，因為 UWB Z軸向前，螢幕 Y軸向下
        )
    }

    static func == (lhs: NearbyDevice, rhs: NearbyDevice) -> Bool {
        lhs.id == rhs.id && 
        lhs.distance == rhs.distance && 
        lhs.direction == rhs.direction &&
        lhs.displayName == rhs.displayName
    }
}
