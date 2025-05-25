import SwiftUI

#if os(iOS)
import NearbyInteraction
import MultipeerConnectivity
import UIKit

// MARK: - 裝置資料模型
struct NearbyDevice: Identifiable, Equatable {
    let id: MCPeerID
    var displayName: String
    var distance: Float?
    var direction: simd_float3?
    
    static func == (lhs: NearbyDevice, rhs: NearbyDevice) -> Bool {
        lhs.id == rhs.id &&
        lhs.distance == rhs.distance &&
        lhs.direction == rhs.direction
    }
}

// MARK: - NearbyInteraction 管理器
class NIManager: NSObject, ObservableObject {
    @Published var devices: [MCPeerID: NearbyDevice] = [:]
    @Published var status: String = "等待中..."
    
    // 改為多 session 架構
    private var niSessions: [MCPeerID: NISession] = [:]
    private let serviceType = "vectorchat"
    private var myPeerID: MCPeerID
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    private var sessions: [MCPeerID: MCSession] = [:]
    private var tokenMap: [NIDiscoveryToken: MCPeerID] = [:]
    private var pendingInvitations: Set<MCPeerID> = []
    private let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    
    override init() {
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["uuid": deviceUUID], serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        
        super.init()
        
        guard NISession.isSupported else {
            status = "此裝置不支援 UWB"
            return
        }
        
        // setupNISession 不再需要
        // setupNISession()
        setupMultipeer()
        start()
    }
    
    private func setupMultipeer() {
        advertiser.delegate = self
        browser.delegate = self
    }
    
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        status = "開始掃描裝置..."
    }
    
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        // 多 session 架構下全部 invalidate
        niSessions.values.forEach { $0.invalidate() }
        niSessions.removeAll()
        sessions.values.forEach { $0.disconnect() }
        sessions.removeAll()
        devices.removeAll()
        status = "已停止"
    }
    
    private func sendToken(to peerID: MCPeerID) {
        // 重複檢查連接狀態，確保穩定
        guard let token = niSessions[peerID]?.discoveryToken else {
            print("無法獲取 NI Discovery Token")
            // 延遲重試一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.sendToken(to: peerID)
            }
            return
        }
        
        guard let session = sessions[peerID] else {
            print("找不到與 \(peerID.displayName) 的 session")
            return
        }
        
        guard session.connectedPeers.contains(peerID) else {
            print("與 \(peerID.displayName) 的連接尚未建立，等待連接...")
            // 延遲重試，等待連接穩定
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.sendToken(to: peerID)
            }
            return
        }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try session.send(data, toPeers: [peerID], with: .reliable)
            print("✅ 成功發送 token 給 \(peerID.displayName)")
            
            DispatchQueue.main.async {
                self.status = "已發送 token 給 \(peerID.displayName)"
            }
        } catch {
            print("❌ 發送 token 給 \(peerID.displayName) 失敗: \(error)")
            
            // 如果發送失敗，延遲重試一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.retrySendToken(to: peerID)
            }
        }
    }
    
    private func retrySendToken(to peerID: MCPeerID) {
        guard let token = niSessions[peerID]?.discoveryToken,
              let session = sessions[peerID],
              session.connectedPeers.contains(peerID) else {
            print("❌ 重試發送 token 失敗：連接已斷開或 session 不存在")
            return
        }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try session.send(data, toPeers: [peerID], with: .reliable)
            print("✅ 重試成功：已發送 token 給 \(peerID.displayName)")
            
            DispatchQueue.main.async {
                self.status = "重試發送成功給 \(peerID.displayName)"
            }
        } catch {
            print("❌ 重試發送 token 給 \(peerID.displayName) 仍然失敗: \(error)")
            
            DispatchQueue.main.async {
                self.status = "發送 token 失敗: \(peerID.displayName)"
            }
        }
    }
}

// MARK: - NISessionDelegate
extension NIManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            guard let peerID = tokenMap[object.discoveryToken] else { continue }
            
            DispatchQueue.main.async {
                if var device = self.devices[peerID] {
                    device.distance = object.distance
                    device.direction = object.direction
                    self.devices[peerID] = device
                    
                    // print("📍 更新 \(peerID.displayName): 距離 \(String(format: "%.2f", object.distance ?? 0))m")
                    
                    // 只有當有距離資料時才更新狀態
                    if object.distance != nil {
                        self.status = "正在測距 - 已連接 \(self.devices.count) 台裝置"
                    }
                }
            }
        }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        for object in nearbyObjects {
            guard let peerID = tokenMap[object.discoveryToken] else { continue }
            DispatchQueue.main.async {
                print("📍 移除 \(peerID.displayName) 的距離資料，原因: \(reason)")
                if var device = self.devices[peerID] {
                    device.distance = nil
                    device.direction = nil
                    self.devices[peerID] = device
                }
                self.tokenMap.removeValue(forKey: object.discoveryToken)
                self.status = "失去距離資料: \(peerID.displayName)"
            }
        }
    }
    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("❌ NI Session 失效: \(error)")
        // 找出是哪個 peer 的 session
        if let peerID = niSessions.first(where: { $0.value == session })?.key {
            niSessions.removeValue(forKey: peerID)
            print("🧹 已移除失效的 NISession: \(peerID.displayName)")
        }
        DispatchQueue.main.async {
            self.status = "NI Session 失效: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension NIManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        sessions[peerID] = session
        
        invitationHandler(true, session)
        print("接受來自 \(peerID.displayName) 的邀請")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("廣播失敗: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension NIManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("發現裝置: \(peerID.displayName)")
        
        // 檢查是否已經有連接或正在處理
        guard sessions[peerID] == nil, !pendingInvitations.contains(peerID) else {
            print("裝置 \(peerID.displayName) 已經在處理中，跳過")
            return
        }
        
        // 使用 UUID 來決定誰發送邀請，避免雙向邀請
        if let peerUUID = info?["uuid"], deviceUUID < peerUUID {
            print("本機 UUID 較小，發送邀請給 \(peerID.displayName)")
            
            let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            sessions[peerID] = session
            pendingInvitations.insert(peerID)
            
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
            print("已向 \(peerID.displayName) 發送邀請")
        } else {
            print("等待來自 \(peerID.displayName) 的邀請")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("失去裝置: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("瀏覽失敗: \(error)")
    }
}

// MARK: - MCSessionDelegate
extension NIManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("✅ 已連接: \(peerID.displayName)")
                self.devices[peerID] = NearbyDevice(id: peerID, displayName: peerID.displayName)
                self.pendingInvitations.remove(peerID)
                self.status = "已連接: \(peerID.displayName)"

                // 確保 NISession 存在於此 peer
                if self.niSessions[peerID] == nil {
                    let newNISession = NISession()
                    newNISession.delegate = self
                    self.niSessions[peerID] = newNISession
                    print("🔧 為 \(peerID.displayName) 建立 NISession (在 MC 連接成功時)")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("🔄 延遲 2 秒後發送 token 給 \(peerID.displayName)")
                    self.sendToken(to: peerID)
                }
            case .notConnected:
                print("❌ 斷開連接: \(peerID.displayName)")
                self.devices.removeValue(forKey: peerID)
                self.sessions.removeValue(forKey: peerID)
                self.pendingInvitations.remove(peerID)
                // 清理 token 映射
                if let tokenToRemove = self.tokenMap.first(where: { $0.value == peerID })?.key {
                    self.tokenMap.removeValue(forKey: tokenToRemove)
                    print("🧹 清理 token 映射: \(peerID.displayName)")
                }
                // 清理對應 NISession
                if let niSession = self.niSessions[peerID] {
                    niSession.invalidate()
                    self.niSessions.removeValue(forKey: peerID)
                    print("🧹 清理 NISession: \(peerID.displayName)")
                }
                if self.devices.isEmpty {
                    self.status = "無連接裝置"
                } else {
                    self.status = "已連接 \(self.devices.count) 台裝置"
                }
            case .connecting:
                print("🔄 正在連接: \(peerID.displayName)")
                self.status = "正在連接: \(peerID.displayName)"
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("📨 從 \(peerID.displayName) 收到資料，長度: \(data.count) bytes")
        do {
            if let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
                print("✅ 成功解析來自 \(peerID.displayName) 的 NI token")
                tokenMap[token] = peerID
                // 為每個 peer 建立/取得獨立 NISession
                let niSession: NISession
                if let existing = niSessions[peerID] {
                    niSession = existing
                } else {
                    niSession = NISession()
                    niSession.delegate = self
                    niSessions[peerID] = niSession
                }
                DispatchQueue.main.async {
                    self.status = "收到 \(peerID.displayName) 的 token，準備配置 NI..."
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    let config = NINearbyPeerConfiguration(peerToken: token)
                    niSession.run(config)
                    print("✅ 已為 \(peerID.displayName) 配置並啟動 NI")
                    DispatchQueue.main.async {
                        self.status = "NI 已啟動: \(peerID.displayName)"
                    }
                }
            } else {
                print("❌ 無法解析來自 \(peerID.displayName) 的資料為 NI token")
                DispatchQueue.main.async {
                    self.status = "Token 解析失敗: \(peerID.displayName)"
                }
            }
        } catch {
            print("❌ 處理來自 \(peerID.displayName) 的資料失敗: \(error)")
            DispatchQueue.main.async {
                self.status = "資料處理失敗: \(peerID.displayName)"
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - UI 視圖
struct ContentView: View {
    @StateObject private var manager = NIManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 狀態顯示
                Text(manager.status)
                    .font(.headline)
                    .padding()
                
                // 裝置列表
                List {
                    ForEach(Array(manager.devices.values)) { device in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.displayName)
                                .font(.headline)
                            
                            if let distance = device.distance {
                                Text("距離: \(String(format: "%.2f", distance))m")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else {
                                Text("距離: 偵測中...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            if let direction = device.direction {
                                Text("方向: (\(String(format: "%.1f", direction.x)), \(String(format: "%.1f", direction.z)))")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 控制按鈕
                HStack(spacing: 20) {
                    Button("重新開始") {
                        manager.stop()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            manager.start()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("停止") {
                        manager.stop()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("UWB 最小測試")
        }
    }
}

#else
// macOS 版本 - 顯示不支援訊息
struct ContentView: View {
    var body: some View {
        VStack {
            Text("此應用需要在 iOS 裝置上運行")
                .font(.headline)
            Text("UWB/NearbyInteraction 只支援 iOS")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
    }
}
#endif

// MARK: - App 入口
@main
struct UWB_testApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}