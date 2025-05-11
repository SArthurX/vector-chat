import Foundation
import MultipeerConnectivity
import simd

struct PeerDevice: Identifiable {
    let id: MCPeerID
    var name: String { id.displayName }
    
    // UWB 即時資料
    var distance: Float?        // 公尺
    var direction: simd_float3? // -1…1 向量
    
    // UI 座標（由 ViewModel 計算）
    var uiX: CGFloat = 0
    var uiY: CGFloat = 0

    var connected = false          // 是否已在 MCSession 中
    var tokenExchanged = false    // 是否已交換 UWB token
}
