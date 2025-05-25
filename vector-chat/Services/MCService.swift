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

/// MultipeerConnectivity 服務管理類別 - 支持多裝置網狀網絡
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
    private var mcSession: MCSession  // 單一 Session 管理所有連接
    private var pendingInvitations: Set<MCPeerID> = []
    private var connectingPeers: Set<MCPeerID> = []
    
    // 新增：追蹤 Discovery Token 發送狀態
    private var sentTokenToPeers: Set<MCPeerID> = []
    private var isInitialTokenSent = false
    
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
        
        // 創建單一 MCSession 來管理所有連接
        self.mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        
        super.init()
        
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self
        self.mcSession.delegate = self
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
        mcSession.disconnect()
        
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
            self.discoveredPeers.removeAll()
        }
        
        pendingInvitations.removeAll()
        connectingPeers.removeAll()
        sentTokenToPeers.removeAll()
        isInitialTokenSent = false
    }
    
    func sendDiscoveryToken(_ token: NIDiscoveryToken) {
        guard !mcSession.connectedPeers.isEmpty else {
            debuglog("沒有連接的 Peers，無法發送 Discovery Token")
            return
        }
        
        // 只發送給尚未收到 token 的新連接設備
        let newPeers = Set(mcSession.connectedPeers).subtracting(sentTokenToPeers)
        
        guard !newPeers.isEmpty else {
            debuglog("所有已連接的 Peers 都已收到 Discovery Token，跳過發送")
            return
        }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try mcSession.send(data, toPeers: Array(newPeers), with: .reliable)
            
            // 記錄已發送的 peers
            sentTokenToPeers.formUnion(newPeers)
            
            debuglog("已傳送 Discovery Token 給 \(newPeers.count) 個新連接的 peers")
            for peer in newPeers {
                debuglog("  -> \(peer.displayName.prefix(5))")
            }
        } catch {
            debuglog("傳送 Discovery Token 失敗: \(error.localizedDescription)")
        }
    }
    
    func disconnectPeer(_ peerID: MCPeerID) {
        // 在網狀網絡中，我們不能選擇性斷開單個 peer
        // 但我們可以從本地狀態中移除它
        DispatchQueue.main.async {
            self.connectedPeers.remove(peerID)
        }
        
        // 清理 token 發送記錄
        sentTokenToPeers.remove(peerID)
        
        debuglog("從本地狀態移除 peer: \(peerID.displayName)")
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
        
        // 接受邀請，使用共享的 mcSession
        invitationHandler(true, mcSession)
        debuglog("已接受來自 \(peerID.displayName.prefix(5)) 的連接邀請")
        
        // 移除待處理的邀請狀態
        pendingInvitations.remove(peerID)
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
        
        // 使用 UUID 來決定誰發送邀請（防止雙向邀請衝突）
        if let peerUUID = info?["uuid"], shouldInitiateConnection(to: peerUUID) {
            debuglog("本機 UUID 字典序較小，發送邀請給 \(peerID.displayName.prefix(5))")
            
            pendingInvitations.insert(peerID)
            connectingPeers.insert(peerID)
            
            browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 30)
            debuglog("已向 \(peerID.displayName.prefix(5)) 發送連接邀請")
        } else {
            debuglog("本機 UUID 字典序較大或無法比較，等待對方邀請 \(peerID.displayName.prefix(5))")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        debuglog("裝置消失 (MPC): \(peerID.displayName.prefix(5))")
        
        DispatchQueue.main.async {
            self.discoveredPeers.remove(peerID)
        }
        
        // 清理本地狀態
        pendingInvitations.remove(peerID)
        connectingPeers.remove(peerID)
        sentTokenToPeers.remove(peerID)
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
                debuglog("MCP Session 與 \(peerID.displayName.prefix(5)) 已連接")
                self.connectedPeers.insert(peerID)
                self.pendingInvitations.remove(peerID)
                self.connectingPeers.remove(peerID)
                
                debuglog("目前已連接的裝置數: \(self.connectedPeers.count)")
                
                // 觸發回調，通知有新的連接建立
                self.onPeerConnected?()
                
            case .connecting:
                debuglog("MCP Session 與 \(peerID.displayName.prefix(5)) 正在連接...")
                
            case .notConnected:
                debuglog("MCP Session 與 \(peerID.displayName.prefix(5)) 未連接或已斷開")
                self.connectedPeers.remove(peerID)
                self.pendingInvitations.remove(peerID)
                self.connectingPeers.remove(peerID)
                self.sentTokenToPeers.remove(peerID)
                
            @unknown default:
                debuglog("MCP Session 與 \(peerID.displayName.prefix(5)) 狀態未知")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        debuglog("從 \(peerID.displayName.prefix(5)) 收到資料，長度: \(data.count)")
        
        do {
            if let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
                debuglog("成功從 \(peerID.displayName.prefix(5)) 收到 Discovery Token")
                onDiscoveryTokenReceived?(peerID, discoveryToken)
            }
        } catch {
            debuglog("解碼 Discovery Token 失敗: \(error.localizedDescription)")
        }
    }
    
    // 以下方法在此範例中未使用，但必須實作
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        debuglog("MCSession: didReceive stream from \(peerID.displayName.prefix(5))")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        debuglog("MCSession: didStartReceivingResourceWithName \(resourceName) from \(peerID.displayName.prefix(5))")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            debuglog("MCSession: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName.prefix(5)) with error: \(error.localizedDescription)")
        } else {
            debuglog("MCSession: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName.prefix(5)) successfully")
        }
    }
}