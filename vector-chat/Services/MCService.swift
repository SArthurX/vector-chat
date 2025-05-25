//
//  MCService.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Combine



/// MultipeerConnectivity 服務管理類別
class MCService: NSObject, ObservableObject {
    // MARK: - Published 屬性
    @Published var connectedPeers: Set<MCPeerID> = []
    @Published var discoveredPeers: Set<MCPeerID> = []
    
    // MARK: - 私有屬性
    private let serviceType = "vectorchat"
    private let deviceUUID: String
    private var myPeerID: MCPeerID
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private var serviceBrowser: MCNearbyServiceBrowser
    private var activeSessions: [MCSession] = []
    private var sessionToPeers: [MCSession: MCPeerID] = [:]
    private var peerToSession: [MCPeerID: MCSession] = [:]
    private var pendingInvitations: Set<MCPeerID> = []
    private var connectingPeers: Set<MCPeerID> = []
    
    // MARK: - 回調
    var onDiscoveryTokenReceived: ((MCPeerID, NIDiscoveryToken) -> Void)?
    var onPeerConnected: (() -> Void)?
    
    // MARK: - 初始化
    override init() {
        self.deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.myPeerID = MCPeerID(displayName: deviceUUID)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["uuid": deviceUUID],
            serviceType: serviceType
        )
        self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        
        super.init()
        
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self
        
        debuglog("本機 PeerID: \(myPeerID.displayName.prefix(5))")
    }
    
    deinit {
        stop()
    }
    
    // MARK: - 公開方法
    func start() {
        startBrowsing()
        startAdvertising()
    }
    
    func stop() {
        stopAdvertising()
        stopBrowsing()
        
        // 斷開所有連接
        activeSessions.forEach { $0.disconnect() }
        activeSessions.removeAll()
        sessionToPeers.removeAll()
        peerToSession.removeAll()
        
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
            self.discoveredPeers.removeAll()
        }
    }
    
    func sendDiscoveryToken(_ token: NIDiscoveryToken) {
        guard !activeSessions.isEmpty else {
            debuglog("沒有活動的 MCSession，無法發送 Discovery Token")
            return
        }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            
            for session in activeSessions {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                debuglog("已傳送 Discovery Token 給 session 中的所有 peers")
            }
        } catch {
            debuglog("傳送 Discovery Token 失敗: \(error.localizedDescription)")
        }
    }
    
    func disconnectPeer(_ peerID: MCPeerID) {
        if let session = peerToSession[peerID] {
            session.disconnect()
            peerToSession.removeValue(forKey: peerID)
            
            if let index = activeSessions.firstIndex(of: session) {
                activeSessions.remove(at: index)
            }
            sessionToPeers.removeValue(forKey: session)
        }
        
        DispatchQueue.main.async {
            self.connectedPeers.remove(peerID)
        }
    }
    
    // MARK: - 私有方法
    private func startAdvertising() {
        serviceAdvertiser.startAdvertisingPeer()
        debuglog("開始廣播服務: \(serviceType)")
    }
    
    private func stopAdvertising() {
        serviceAdvertiser.stopAdvertisingPeer()
        print("停止廣播服務")
    }
    
    private func startBrowsing() {
        serviceBrowser.startBrowsingForPeers()
        debuglog("開始瀏覽附近裝置: \(serviceType)")
    }
    
    private func stopBrowsing() {
        serviceBrowser.stopBrowsingForPeers()
        print("停止瀏覽附近裝置")
    }
    
    private func shouldInitiateConnection(to peerUUID: String) -> Bool {
        return deviceUUID < peerUUID
    }
    
    private func createSession(for peerID: MCPeerID) -> MCSession {
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        activeSessions.append(session)
        sessionToPeers[session] = peerID
        peerToSession[peerID] = session
        
        return session
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MCService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        debuglog("收到來自 \(peerID.displayName) 的連接邀請")
        
        // 檢查是否已經與此 peer 連接
        if connectedPeers.contains(peerID) {
            debuglog("與 \(peerID.displayName) 已經建立連接，拒絕邀請")
            invitationHandler(false, nil)
            return
        }
        
        // 檢查是否正在等待此 peer 的邀請響應
        if pendingInvitations.contains(peerID) {
            debuglog("接受到 \(peerID.displayName) 的邀請，但本機也有 pending invite，接受對方優先")
            pendingInvitations.remove(peerID)
            
            // 如果有現有的 session 在嘗試連接，先斷開
            if let existingSession = peerToSession[peerID] {
                existingSession.disconnect()
                if let index = activeSessions.firstIndex(of: existingSession) {
                    activeSessions.remove(at: index)
                }
                sessionToPeers.removeValue(forKey: existingSession)
            }
        }
        
        let session = createSession(for: peerID)
        invitationHandler(true, session)
        debuglog("已接受來自 \(peerID.displayName) 的連接邀請")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        debuglog("服務廣播啟動失敗: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MCService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        debuglog("發現裝置: \(peerID.displayName)")
        
        DispatchQueue.main.async {
            self.discoveredPeers.insert(peerID)
        }
        
        // 檢查是否已連接或正在連接
        guard !connectedPeers.contains(peerID) && !connectingPeers.contains(peerID) else {
            debuglog("裝置 \(peerID.displayName) 已連接或正在連接，忽略此次發現")
            return
        }
        
        // 檢查是否已有等待中的邀請
        guard !pendingInvitations.contains(peerID) else {
            debuglog("已存在等待中的邀請給 \(peerID.displayName)，跳過")
            return
        }
        
        // 使用 UUID 來決定誰發送邀請
        if let peerUUID = info?["uuid"], shouldInitiateConnection(to: peerUUID) {
            debuglog("本機 UUID 字典序較小，發送邀請給 \(peerID.displayName)")
            
            let session = createSession(for: peerID)
            pendingInvitations.insert(peerID)
            connectingPeers.insert(peerID)
            
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
            debuglog("已向 \(peerID.displayName) 發送連接邀請")
        } else {
            debuglog("本機 UUID 字典序較大或無法比較，等待對方邀請 \(peerID.displayName)")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        debuglog("裝置消失 (MPC): \(peerID.displayName)")
        
        DispatchQueue.main.async {
            self.discoveredPeers.remove(peerID)
        }
        
        // 斷開連接
        disconnectPeer(peerID)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        debuglog("裝置瀏覽啟動失敗: \(error.localizedDescription)")
    }
}

// MARK: - MCSessionDelegate
extension MCService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                debuglog("MCP Session 與 \(peerID.displayName) 已連接")
                self.connectedPeers.insert(peerID)
                self.pendingInvitations.remove(peerID)
                self.connectingPeers.remove(peerID)
                
                // 觸發回調，通知有新的連接建立
                self.onPeerConnected?()
                
            case .connecting:
                debuglog("MCP Session 與 \(peerID.displayName) 正在連接...")
                
            case .notConnected:
                debuglog("MCP Session 與 \(peerID.displayName) 未連接或已斷開")
                self.connectedPeers.remove(peerID)
                self.pendingInvitations.remove(peerID)
                self.connectingPeers.remove(peerID)
                
                // 清理 session 相關資料
                if let sessionToRemove = self.peerToSession[peerID] {
                    self.peerToSession.removeValue(forKey: peerID)
                    self.sessionToPeers.removeValue(forKey: sessionToRemove)
                    
                    if let index = self.activeSessions.firstIndex(of: sessionToRemove) {
                        self.activeSessions.remove(at: index)
                    }
                }
                
            @unknown default:
                print("MCP Session 與 \(peerID.displayName) 狀態未知")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        debuglog("從 \(peerID.displayName) 收到資料，長度: \(data.count)")
        
        do {
            if let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
                debuglog("成功從 \(peerID.displayName) 收到 Discovery Token")
                onDiscoveryTokenReceived?(peerID, discoveryToken)
            }
        } catch {
            debuglog("解碼 Discovery Token 失敗: \(error.localizedDescription)")
        }
    }
    
    // 以下方法在此範例中未使用，但必須實作
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        debuglog("MCSession: didReceive stream from \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        debuglog("MCSession: didStartReceivingResourceWithName \(resourceName) from \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            debuglog("MCSession: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName) with error: \(error.localizedDescription)")
        } else {
            debuglog("MCSession: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName) successfully")
        }
    }
}
