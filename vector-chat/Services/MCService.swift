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
import UIKit

/// MultipeerConnectivity 服務管理類別 - 支持多裝置獨立連接
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
    
    // 改用多個獨立 Session - 每對裝置一個 Session
    private var peerSessions: [MCPeerID: MCSession] = [:]
    private var pendingInvitations: Set<MCPeerID> = []
    private var connectingPeers: Set<MCPeerID> = []
    private var connectionAttempts: [MCPeerID: Int] = [:]
    private var lastConnectionTime: [MCPeerID: Date] = [:]
    private let maxConnectionAttempts = 3
    private let connectionCooldown: TimeInterval = 10.0
    // 追蹤已發送 Discovery Token 的 peers
    private var tokenSentToPeers: Set<MCPeerID> = []
    private var tokenSendingQueue = DispatchQueue(label: "tokenSending", qos: .utility)
    
    // MARK: - 回調
    var onDiscoveryTokenReceived: ((MCPeerID, NIDiscoveryToken) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    
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
        debuglog("MCService 初始化完成，本機 PeerID: \(myPeerID.displayName.prefix(5))")
    }
    
    deinit {
        stop()
    }
    
    // MARK: - 公開方法
    func start() {
        debuglog("MCService 啟動")
        startBrowsing()
        startAdvertising()
    }
    
    func stop() {
        debuglog("MCService 停止")
        stopAdvertising()
        stopBrowsing()
        
        // 斷開所有獨立的 sessions
        for (peerID, session) in peerSessions {
            debuglog("斷開與 \(peerID.displayName.prefix(5)) 的獨立連接")
            session.disconnect()
        }
        
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
            self.discoveredPeers.removeAll()
        }
        
        peerSessions.removeAll()
        pendingInvitations.removeAll()
        connectingPeers.removeAll()
        connectionAttempts.removeAll()
        lastConnectionTime.removeAll()
    }
    
    func sendDiscoveryToken(_ token: NIDiscoveryToken) {
        guard !connectedPeers.isEmpty else {
            debuglog("沒有連接的 Peers，無法發送 Discovery Token")
            return
        }
        
        // 使用序列化隊列避免同時發送衝突，只向尚未發送的 peers 發送
        tokenSendingQueue.async { [weak self] in
            guard let self = self else { return }
            
            var successCount = 0
            
            for (peerID, session) in self.peerSessions {
                // 檢查是否已連接且尚未發送過 token
                if session.connectedPeers.contains(peerID) && !self.tokenSentToPeers.contains(peerID) {
                    do {
                        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                        try session.send(data, toPeers: [peerID], with: .reliable)
                        
                        // 標記為已發送
                        DispatchQueue.main.async {
                            self.tokenSentToPeers.insert(peerID)
                        }
                        
                        successCount += 1
                        debuglog("成功傳送 Discovery Token 給 \(peerID.displayName.prefix(5))")
                    } catch {
                        debuglog("傳送 Discovery Token 給 \(peerID.displayName.prefix(5)) 失敗: \(error.localizedDescription)")
                    }
                } else if self.tokenSentToPeers.contains(peerID) {
                    debuglog("已向 \(peerID.displayName.prefix(5)) 發送過 Discovery Token，跳過")
                }
            }
            
            debuglog("已傳送 Discovery Token 給 \(successCount) 個新連接的 peers")
        }
    }
    
    func sendDiscoveryToken(_ token: NIDiscoveryToken, to peerID: MCPeerID) -> Bool {
        guard let session = peerSessions[peerID],
              session.connectedPeers.contains(peerID) else {
            debuglog("無法向 \(peerID.displayName.prefix(5)) 發送 token：連接不存在或未建立")
            return false
        }
        
        var success = false
        tokenSendingQueue.sync { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                try session.send(data, toPeers: [peerID], with: .reliable)
                
                // 標記為已發送
                DispatchQueue.main.async {
                    self.tokenSentToPeers.insert(peerID)
                }
                
                debuglog("成功傳送 Discovery Token 給 \(peerID.displayName.prefix(5))")
                success = true
            } catch {
                debuglog("傳送 Discovery Token 給 \(peerID.displayName.prefix(5)) 失敗: \(error.localizedDescription)")
                success = false
            }
        }
        
        return success
    }
    
    func disconnectPeer(_ peerID: MCPeerID) {
        if let session = peerSessions[peerID] {
            session.disconnect()
            peerSessions.removeValue(forKey: peerID)
            debuglog("斷開與 \(peerID.displayName.prefix(5)) 的獨立連接")
        }
        
        DispatchQueue.main.async {
            self.connectedPeers.remove(peerID)
            self.tokenSentToPeers.remove(peerID)  // 清理發送狀態
        }
    }
    
    // MARK: - 私有方法
    private func startAdvertising() {
        serviceAdvertiser.startAdvertisingPeer()
        debuglog("開始廣播服務: \(serviceType)")
    }
    
    private func stopAdvertising() {
        serviceAdvertiser.stopAdvertisingPeer()
        debuglog("停止廣播服務")
    }
    
    private func startBrowsing() {
        serviceBrowser.startBrowsingForPeers()
        debuglog("開始瀏覽附近裝置: \(serviceType)")
    }
    
    private func stopBrowsing() {
        serviceBrowser.stopBrowsingForPeers()
        debuglog("停止瀏覽附近裝置")
    }
    
    private func shouldInitiateConnection(to peerUUID: String) -> Bool {
        return deviceUUID < peerUUID
    }
    
    private func canAttemptConnection(to peerID: MCPeerID) -> Bool {
        // 檢查連接嘗試次數
        if let attempts = connectionAttempts[peerID], attempts >= maxConnectionAttempts {
            debuglog("達到最大連接嘗試次數，跳過 \(peerID.displayName.prefix(5))")
            return false
        }
        
        // 檢查冷卻時間
        if let lastTime = lastConnectionTime[peerID],
           Date().timeIntervalSince(lastTime) < connectionCooldown {
            debuglog("連接冷卻時間未到，跳過 \(peerID.displayName.prefix(5))")
            return false
        }
        
        return true
    }
    
    private func recordConnectionAttempt(for peerID: MCPeerID) {
        connectionAttempts[peerID, default: 0] += 1
        lastConnectionTime[peerID] = Date()
        debuglog("記錄連接嘗試 \(connectionAttempts[peerID] ?? 0) 給 \(peerID.displayName.prefix(5))")
    }
    
    private func resetConnectionAttempts(for peerID: MCPeerID) {
        connectionAttempts.removeValue(forKey: peerID)
        lastConnectionTime.removeValue(forKey: peerID)
        debuglog("重置連接嘗試計數器給 \(peerID.displayName.prefix(5))")
    }
    
    private func createSessionForPeer(_ peerID: MCPeerID) -> MCSession {
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        peerSessions[peerID] = session
        debuglog("為 \(peerID.displayName.prefix(5)) 創建獨立 MCSession")
        return session
    }
    
    private func getOrCreateSession(for peerID: MCPeerID) -> MCSession {
        if let existingSession = peerSessions[peerID] {
            return existingSession
        }
        return createSessionForPeer(peerID)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MCService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        debuglog("收到來自 \(peerID.displayName.prefix(5)) 的連接邀請")
        
        // 檢查是否已經與此 peer 連接
        if connectedPeers.contains(peerID) {
            debuglog("與 \(peerID.displayName.prefix(5)) 已經建立連接，拒絕邀請")
            invitationHandler(false, nil)
            return
        }
        
        // 檢查是否超過連接數限制
        if connectedPeers.count >= 8 {
            debuglog("已達到最大連接數，拒絕來自 \(peerID.displayName.prefix(5)) 的邀請")
            invitationHandler(false, nil)
            return
        }
        
        // 為此 peer 創建或獲取獨立的 session
        let session = getOrCreateSession(for: peerID)
        
        // 接受邀請
        invitationHandler(true, session)
        debuglog("已接受來自 \(peerID.displayName.prefix(5)) 的連接邀請，使用獨立 Session")
        
        // 清理狀態
        pendingInvitations.remove(peerID)
        resetConnectionAttempts(for: peerID)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        debuglog("服務廣播啟動失敗: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MCService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        debuglog("發現裝置: \(peerID.displayName.prefix(5))")
        
        DispatchQueue.main.async {
            self.discoveredPeers.insert(peerID)
        }
        
        // 檢查是否已連接或正在連接
        guard !connectedPeers.contains(peerID) && !connectingPeers.contains(peerID) else {
            debuglog("裝置 \(peerID.displayName.prefix(5)) 已連接或正在連接，忽略此次發現")
            return
        }
        
        // 檢查是否已有等待中的邀請
        guard !pendingInvitations.contains(peerID) else {
            debuglog("已存在等待中的邀請給 \(peerID.displayName.prefix(5))，跳過")
            return
        }
        
        // 檢查連接能力
        guard canAttemptConnection(to: peerID) else {
            return
        }
        
        // 檢查連接數限制
        if connectedPeers.count >= 8 {
            debuglog("已達到最大連接數，跳過 \(peerID.displayName.prefix(5))")
            return
        }
        
        // 使用 UUID 來決定誰發送邀請（防止雙向邀請衝突）
        if let peerUUID = info?["uuid"], shouldInitiateConnection(to: peerUUID) {
            debuglog("本機 UUID 字典序較小，發送邀請給 \(peerID.displayName.prefix(5))")
            
            pendingInvitations.insert(peerID)
            connectingPeers.insert(peerID)
            recordConnectionAttempt(for: peerID)
            
            // 為此 peer 創建獨立的 session
            let session = getOrCreateSession(for: peerID)
            
            // 添加短暫延遲避免衝突
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.1...0.5)) {
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
                debuglog("已向 \(peerID.displayName.prefix(5)) 發送連接邀請，使用獨立 Session")
            }
        } else {
            debuglog("本機 UUID 字典序較大或無法比較，等待對方邀請 \(peerID.displayName.prefix(5))")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        debuglog("裝置消失 (MCP): \(peerID.displayName.prefix(5))")
        
        DispatchQueue.main.async {
            self.discoveredPeers.remove(peerID)
        }
        
        // 清理本地狀態
        pendingInvitations.remove(peerID)
        connectingPeers.remove(peerID)
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
                debuglog("獨立 Session 與 \(peerID.displayName.prefix(5)) 已連接")
                self.connectedPeers.insert(peerID)
                self.pendingInvitations.remove(peerID)
                self.connectingPeers.remove(peerID)
                self.resetConnectionAttempts(for: peerID)
                
                debuglog("目前已連接的裝置數: \(self.connectedPeers.count)")
                
                // 延遲觸發連接回調，確保連接穩定
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.connectedPeers.contains(peerID) && session.connectedPeers.contains(peerID) {
                        debuglog("確認 \(peerID.displayName.prefix(5)) 連接穩定，觸發回調")
                        self.onPeerConnected?(peerID)
                    }
                }
                
            case .connecting:
                debuglog("獨立 Session 與 \(peerID.displayName.prefix(5)) 正在連接...")
                
            case .notConnected:
                debuglog("獨立 Session 與 \(peerID.displayName.prefix(5)) 未連接或已斷開")
                self.connectedPeers.remove(peerID)
                self.pendingInvitations.remove(peerID)
                self.connectingPeers.remove(peerID)
                self.tokenSentToPeers.remove(peerID)  // 清理發送狀態
                
                // 清理對應的 session
                if self.peerSessions[peerID] === session {
                    self.peerSessions.removeValue(forKey: peerID)
                    debuglog("清理 \(peerID.displayName.prefix(5)) 的獨立 Session")
                }
                
            @unknown default:
                debuglog("獨立 Session 與 \(peerID.displayName.prefix(5)) 狀態未知")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        debuglog("從 \(peerID.displayName.prefix(5)) 收到資料，長度: \(data.count)")
        
        // 使用專用隊列處理 Discovery Token 避免主線程阻塞
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                if let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
                    debuglog("成功從 \(peerID.displayName.prefix(5)) 收到 Discovery Token")
                    
                    // 添加延遲處理避免衝突
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.onDiscoveryTokenReceived?(peerID, discoveryToken)
                    }
                }
            } catch {
                debuglog("解碼 Discovery Token 失敗: \(error.localizedDescription)")
            }
        }
    }
    
    // 以下方法在此範例中未使用，但必須實作
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        debuglog("MC Session: didReceive stream from \(peerID.displayName.prefix(5))")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        debuglog("MC Session: didStartReceivingResourceWithName \(resourceName) from \(peerID.displayName.prefix(5))")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            debuglog("MC Session: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName.prefix(5)) with error: \(error.localizedDescription)")
        } else {
            debuglog("MC Session: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName.prefix(5)) successfully")
        }
    }
}
