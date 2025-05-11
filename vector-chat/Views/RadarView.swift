import SwiftUI

struct RadarView: View {
    @EnvironmentObject private var peerManager: PeerConnectionManager
    @EnvironmentObject private var nearbyManager: NearbyInteractionManager
    @StateObject private var vm: RadarViewModel
    
    init() { _vm = StateObject(wrappedValue:
        RadarViewModel(peerManager: Dependency.peer, // 依賴注入
                       nearbyManager: Dependency.nearby))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景圓形網格
                Circle().stroke(.gray.opacity(0.3), lineWidth: 1)
                    .frame(width: 300, height: 300)
                
                // 自己
                Circle()
                    .fill(.blue)
                    .frame(width: 16, height: 16)
                
                // 其他 peer
                ForEach(vm.peers) { peer in
                    let color: Color = peer.connected ? .green : .orange
                    VStack(spacing: 2) {
                        // 圖示按鈕
                        Button {
                            vm.invite(peer, via: peerManager)
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 14, height: 14)
                        }
                        // 除錯文字
                        Text(String(format: "%.2f m", peer.distance ?? -1))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(2)
                            .background(.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    .overlay(                      // 小圓點右上角顯示 token 交換狀態
                        peer.tokenExchanged ?
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                                .offset(x: 8, y: -8)
                        : nil
                    )
                    .offset(x: peer.uiX, y: peer.uiY)
                    .animation(.easeInOut, value: peer.uiX)
                }
            }
            .frame(width: 320, height: 320)
            .navigationTitle("UWB Radar")
        }
    }
}
