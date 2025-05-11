import Foundation
import Combine
import MultipeerConnectivity
import simd
import SwiftUI

@MainActor
final class RadarViewModel: ObservableObject {
    @Published var peers: [PeerDevice] = []
    private var cancellables = Set<AnyCancellable>()
    
    private let maxRadius: CGFloat = 150          // UI 半徑 (px)
    private let metersPerPoint: CGFloat = 0.5     // 1 m => 0.5 px (示例)
    
    init(peerManager: PeerConnectionManager,
         nearbyManager: NearbyInteractionManager) {
        // 監聽 UWB 更新
        nearbyManager.didUpdate
            .sink { [weak self] peerID, distance, direction in
                guard let self else { return }
                var list = self.peers
                if let idx = list.firstIndex(where: { $0.id == peerID }) {
                    var pd = list[idx]
                    pd.distance  = distance
                    pd.direction = direction
                    // 座標換算
                    let x = CGFloat(direction.x * distance) / metersPerPoint
                    let y = CGFloat(direction.y * distance) / metersPerPoint
                    pd.uiX = x
                    pd.uiY = -y                  // y 軸反向
                    list[idx] = pd
                    self.peers = list
                }
            }
            .store(in: &cancellables)
        
        // 監聽 Multipeer 發現
        peerManager.$discoveredPeers
            .sink { [weak self] peerIDs in
                guard let self else { return }
                // 維持 peer 列表順序
                self.peers = peerIDs.map { id in
                    self.peers.first(where: { $0.id == id }) ?? PeerDevice(id: id)
                }
            }
            .store(in: &cancellables)

        peerManager.peerStateChanged
            .sink { [weak self] peerID, connected in
                guard let self,
                    let idx = self.peers.firstIndex(where: { $0.id == peerID }) else { return }
                self.peers[idx].connected = connected
            }
            .store(in: &cancellables)

        peerManager.tokenReceived
            .sink { [weak self] peerID in
                guard let self,
                    let idx = self.peers.firstIndex(where: { $0.id == peerID }) else { return }
                self.peers[idx].tokenExchanged = true
            }
            .store(in: &cancellables)
    }
    
    // 點擊邀請
    func invite(_ peer: PeerDevice, via manager: PeerConnectionManager) {
        manager.invite(peer.id)
    }
}
