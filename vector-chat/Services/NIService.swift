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
    
    // 新增：追蹤已配置的 peers，避免重複配置
    private var configuredPeers: Set<MCPeerID> = []
    
    // 新增：配置隊列，避免同時配置多個peer導致NI Session失效
    private var configurationQueue: [(MCPeerID, NIDiscoveryToken)] = []
    private var isConfiguring = false
    private let configurationDispatchQueue = DispatchQueue(label: "ni.configuration", qos: .userInitiated)
    
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
        configuredPeers.removeAll()
        
        // 清理配置隊列
        configurationDispatchQueue.async { [weak self] in
            self?.configurationQueue.removeAll()
            self?.isConfiguring = false
        }
        
        print("NI Session 已停止並失效")
    }
    
    func runConfiguration(for peerID: MCPeerID, with token: NIDiscoveryToken) {
        // 將配置請求加入隊列
        configurationDispatchQueue.async { [weak self] in
            self?.addToConfigurationQueue(peerID: peerID, token: token)
        }
    }
    
    private func addToConfigurationQueue(peerID: MCPeerID, token: NIDiscoveryToken) {
        // 檢查是否已經在隊列中或已配置
        if configuredPeers.contains(peerID) {
            debuglog("已為 \(peerID.displayName.prefix(5)) 配置過 NI，跳過重複配置")
            return
        }
        
        // 檢查隊列中是否已有相同的請求
        if configurationQueue.contains(where: { $0.0 == peerID }) {
            debuglog("配置請求 \(peerID.displayName.prefix(5)) 已在隊列中，跳過")
            return
        }
        
        // 添加到隊列
        configurationQueue.append((peerID, token))
        debuglog("將 \(peerID.displayName.prefix(5)) 的配置請求加入隊列，隊列長度: \(configurationQueue.count)")
        
        // 如果當前沒有在配置，開始處理隊列
        if !isConfiguring {
            processConfigurationQueue()
        }
    }
    
    private func processConfigurationQueue() {
        guard !configurationQueue.isEmpty, !isConfiguring else { return }
        
        guard let niSession = niSession, !sessionInvalidated else {
            debuglog("NI Session 無效，清空配置隊列")
            configurationQueue.removeAll()
            return
        }
        
        isConfiguring = true
        let (peerID, token) = configurationQueue.removeFirst()
        
        debuglog("開始處理配置隊列，為 \(peerID.displayName.prefix(5)) 配置 NI")
        
        // 檢查是否已經配置過
        if configuredPeers.contains(peerID) {
            debuglog("已為 \(peerID.displayName.prefix(5)) 配置過，跳過並處理下一個")
            isConfiguring = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.configurationDispatchQueue.async {
                    self?.processConfigurationQueue()
                }
            }
            return
        }
        
        // 檢查是否已經有相同的 token
        if let existingPeer = discoveryTokenToPeerMap[token], existingPeer == peerID {
            debuglog("相同的 token 已存在於 \(peerID.displayName.prefix(5))，跳過配置")
            configuredPeers.insert(peerID)
            isConfiguring = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.configurationDispatchQueue.async {
                    self?.processConfigurationQueue()
                }
            }
            return
        }
        
        // 儲存映射關係
        discoveryTokenToPeerMap[token] = peerID
        peerIDToDiscoveryTokenMap[peerID] = token
        configuredPeers.insert(peerID)
        
        let config = NINearbyPeerConfiguration(peerToken: token)
        
        do {
            niSession.run(config)
            debuglog("為 \(peerID.displayName.prefix(5)) 成功運行 NI Configuration")
        } catch {
            debuglog("為 \(peerID.displayName.prefix(5)) 運行 NI Configuration 失敗: \(error.localizedDescription)")
            // 配置失敗時清理狀態
            configuredPeers.remove(peerID)
            discoveryTokenToPeerMap.removeValue(forKey: token)
            peerIDToDiscoveryTokenMap.removeValue(forKey: peerID)
        }
        
        // 配置完成，延遲處理下一個（重要：給NI Session時間處理）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.configurationDispatchQueue.async {
                self?.isConfiguring = false
                self?.processConfigurationQueue()
            }
        }
    }
    
    func removePeer(_ peerID: MCPeerID) {
        if let token = peerIDToDiscoveryTokenMap.removeValue(forKey: peerID) {
            discoveryTokenToPeerMap.removeValue(forKey: token)
        }
        nearbyObjects.removeValue(forKey: peerID)
        configuredPeers.remove(peerID)
        debuglog("已清理 peer: \(peerID.displayName.prefix(5))")
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
        configuredPeers.removeAll() // 清理配置狀態
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
        // debuglog("NI Session 收到更新，物件數量: \(nearbyObjects.count)")
        if nearbyObjects.count > 1{
            debuglog("NI Session 收到更新，物件數量: \(nearbyObjects.count)")
            return
        }
        
        var updatedObjects: [MCPeerID: NINearbyObject] = [:]
        
        for object in nearbyObjects {
            guard let peerID = discoveryTokenToPeerMap[object.discoveryToken] else {
                debuglog("收到未知 Discovery Token 的更新")
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
                debuglog("收到未知 Discovery Token 的移除通知")
                continue
            }
            
            debuglog("NI Session 移除了裝置: \(peerID.displayName.prefix(5)), 原因: \(reason)")
            
            DispatchQueue.main.async {
                self.nearbyObjects.removeValue(forKey: peerID)
                self.discoveryTokenToPeerMap.removeValue(forKey: object.discoveryToken)
                self.peerIDToDiscoveryTokenMap.removeValue(forKey: peerID)
                self.configuredPeers.remove(peerID)
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
        // 清理配置狀態，因為 session 暫停後需要重新配置
        configuredPeers.removeAll()
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        debuglog("NI Session 暫停結束 (Suspension Ended)")
        debuglog("嘗試為已連接的 Peers 重新運行 NI Configuration")
        
        // 清理配置狀態並重置隊列
        configurationDispatchQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.configuredPeers.removeAll()
            self.isConfiguring = false
            self.configurationQueue.removeAll()
            
            // 重新加入所有需要配置的peers到隊列
            for (peerID, token) in self.peerIDToDiscoveryTokenMap {
                self.configurationQueue.append((peerID, token))
                debuglog("重新將 \(peerID.displayName.prefix(5)) 加入配置隊列")
            }
            
            // 開始處理隊列
            self.processConfigurationQueue()
        }
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        debuglog("NI Session 失效: \(error.localizedDescription)")
        sessionInvalidated = true
        
        // 清理所有配置狀態和隊列
        configurationDispatchQueue.async { [weak self] in
            guard let self = self else { return }
            self.configuredPeers.removeAll()
            self.configurationQueue.removeAll()
            self.isConfiguring = false
        }
        
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