//
//  NIService.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import Foundation
import NearbyInteraction
import MultipeerConnectivity
import Combine


/// NearbyInteraction 服務管理類別
class NIService: NSObject, ObservableObject {
    // MARK: - Published 屬性
    @Published var nearbyObjects: [MCPeerID: NINearbyObject] = [:]
    @Published var isSessionInvalidated = false
    
    // MARK: - 私有屬性
    private var niSession: NISession?
    private var sessionInvalidated = false
    private var discoveryTokenToPeerMap: [NIDiscoveryToken: MCPeerID] = [:]
    private var peerIDToDiscoveryTokenMap: [MCPeerID: NIDiscoveryToken] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 回調
    var onDiscoveryTokenReady: ((NIDiscoveryToken) -> Void)?
    var shouldSendToken: (() -> Bool)?
    
    // MARK: - 初始化
    override init() {
        super.init()
        setupLifecycleObservers()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - 公開方法
    func start() {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            print("UWB 不支援於此裝置，無法設定 NI Session")
            isSessionInvalidated = true
            return
        }
        
        setupNISession()
    }
    
    func stop() {
        niSession?.invalidate()
        niSession = nil
        sessionInvalidated = true
        isSessionInvalidated = true
        nearbyObjects.removeAll()
        discoveryTokenToPeerMap.removeAll()
        peerIDToDiscoveryTokenMap.removeAll()
        print("NI Session 已停止並失效")
    }
    
    func runConfiguration(for peerID: MCPeerID, with token: NIDiscoveryToken) {
        guard let niSession = niSession, !sessionInvalidated else {
            debuglog("NI Session 無效，無法運行配置")
            return
        }
        
        // 儲存對方 token 和 peerID 的對應關係
        discoveryTokenToPeerMap[token] = peerID
        peerIDToDiscoveryTokenMap[peerID] = token
        
        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession.run(config)
        debuglog("為 \(peerID.displayName) 運行 NI Configuration")
    }
    
    func removePeer(_ peerID: MCPeerID) {
        if let token = peerIDToDiscoveryTokenMap.removeValue(forKey: peerID) {
            discoveryTokenToPeerMap.removeValue(forKey: token)
        }
        nearbyObjects.removeValue(forKey: peerID)
    }
    
    /// 觸發 Discovery Token 發送（當有 MC 連接時調用）
    func sendDiscoveryTokenIfReady() {
        guard let niSession = niSession, !sessionInvalidated,
              let token = niSession.discoveryToken else {
            debuglog("NI Session 未準備好或無效，無法發送 Discovery Token")
            return
        }
        
        debuglog("觸發 Discovery Token 發送")
        onDiscoveryTokenReady?(token)
    }
    
    // MARK: - NearbyInteraction Session 設定與管理
    private func setupNISession() {
        // 避免重複創建 Session
        guard niSession == nil else {
            debuglog("NI Session 已經存在")
            return
        }
        
        niSession = NISession()
        niSession?.delegate = self
        sessionInvalidated = false
        isSessionInvalidated = false
        debuglog("NI Session 已設定並指派代理")
        
        // 不立即發送 Discovery Token，等待有連接時再發送
        debuglog("NI Session 準備就緒，等待 MC 連接後再發送 Discovery Token")
    }
    
    private func setupLifecycleObservers() {
        // 監聽應用程式生命週期事件
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                print("App 進入背景，NI Session 可能會失效")
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                print("App 返回前景，檢查 NI Session 狀態")
                guard let self = self else { return }
                if self.sessionInvalidated {
                    print("NI Session 已失效，重新設定")
                    self.setupNISession()
                } else if self.niSession == nil && NISession.deviceCapabilities.supportsPreciseDistanceMeasurement {
                    print("NI Session 為 nil，重新設定")
                    self.setupNISession()
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - NISessionDelegate
extension NIService: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        debuglog("NI Session 收到更新，物件數量: \(nearbyObjects.count)")
        
        var updatedObjects: [MCPeerID: NINearbyObject] = [:]
        
        for object in nearbyObjects {
            guard let peerID = discoveryTokenToPeerMap[object.discoveryToken] else {
                debuglog("收到未知 Discovery Token 的更新: \(object.discoveryToken)")
                continue
            }
            updatedObjects[peerID] = object
        }
        
        DispatchQueue.main.async {
            self.nearbyObjects = updatedObjects
        }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        for object in nearbyObjects {
            guard let peerID = discoveryTokenToPeerMap[object.discoveryToken] else {
                debuglog("收到未知 Discovery Token 的移除通知: \(object.discoveryToken)")
                continue
            }
            
            debuglog("NI Session 移除了裝置: \(peerID.displayName), 原因: \(reason)")
            
            DispatchQueue.main.async {
                self.nearbyObjects.removeValue(forKey: peerID)
                self.discoveryTokenToPeerMap.removeValue(forKey: object.discoveryToken)
                self.peerIDToDiscoveryTokenMap.removeValue(forKey: peerID)
            }
            
            // 根據移除原因決定處理方式
            switch reason {
            case .peerEnded:
                print("  原因: 對方結束了 Session")
            case .timeout:
                print("  原因: 連接超時")
            @unknown default:
                print("  原因: 未知")
            }
        }
    }
    
    func sessionWasSuspended(_ session: NISession) {
        print("NI Session 已暫停 (Was Suspended)")
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        debuglog("NI Session 暫停結束 (Suspension Ended)")
        debuglog("嘗試為已連接的 Peers 重新運行 NI Configuration")
        
        for (peerID, token) in peerIDToDiscoveryTokenMap {
            let config = NINearbyPeerConfiguration(peerToken: token)
            debuglog("  為 \(peerID.displayName) 重新運行 NI Configuration")
            niSession?.run(config)
        }
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        debuglog("NI Session 失效: \(error.localizedDescription)")
        sessionInvalidated = true
        
        DispatchQueue.main.async {
            self.isSessionInvalidated = true
        }
        
        // 嘗試重新啟動 Session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if NISession.deviceCapabilities.supportsPreciseDistanceMeasurement {
                debuglog("嘗試重新設定 NI Session...")
                self?.setupNISession()
            }
        }
    }
}
