//
//  NearbyInteractionManager.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import SwiftUI
import NearbyInteraction
import MultipeerConnectivity
import Combine
import simd


/// UWB 和多點連接管理器 (ViewModel)
class NearbyInteractionManager: NSObject, ObservableObject {
    // MARK: - Published 屬性 (UI 會監聽這些變化)
    @Published var nearbyDevices: [MCPeerID: NearbyDevice] = [:] // 儲存偵測到的裝置資訊
    @Published var localDeviceName: String = UIDevice.current.name // 本機裝置名稱
    @Published var isNISessionInvalidated = false // NI Session 是否失效
    @Published var isUnsupportedDevice = false // 是否為不支援 UWB 的裝置

    // MARK: - 服務組件
    private let mcService: MCService
    
    // MARK: - 多 NISession 架構
    private var niSessions: [MCPeerID: NISession] = [:] // 每個 peer 都有獨立的 NISession
    private var tokenMap: [NIDiscoveryToken: MCPeerID] = [:] // token 到 peer 的映射
    
    // MARK: - 其他內部屬性
    private var cancellables = Set<AnyCancellable>() // 用於 Combine

    // MARK: - 初始化
    override init() {
        // 檢查裝置是否支援 UWB
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            print("UWB 不支援於此裝置")
            self.isUnsupportedDevice = true
            // 即使 UWB 不支援，也要初始化服務以避免崩潰
            self.mcService = MCService()
            super.init()
            return
        }

        self.mcService = MCService()
        
        super.init()
        setupBindings()
 
    }

    deinit {
        stop()
        print("NearbyInteractionManager 已釋放")
    }

    // MARK: - 私有方法
    private func setupBindings() {
        // 監聽 MC 服務的連接狀態
        mcService.$connectedPeers
            .sink { [weak self] peers in
                self?.handleMCConnectionsUpdate(peers)
            }
            .store(in: &cancellables)
        
        // 監聽 MC 服務發現的裝置
        mcService.$discoveredPeers
            .sink { [weak self] peers in
                self?.handleMCDiscoveredPeersUpdate(peers)
            }
            .store(in: &cancellables)
        
        // 設置 MC 服務的 Discovery Token 回調
        mcService.onDiscoveryTokenReceived = { [weak self] (peerID: MCPeerID, token: NIDiscoveryToken) in
            self?.handleReceivedToken(from: peerID, token: token)
        }
        
        // 設置 MC 服務的連接回調，觸發 Discovery Token 發送
        mcService.onPeerConnected = { [weak self] (peerID: MCPeerID) in
            // 延遲發送，確保連接穩定後再發送 Discovery Token
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.sendDiscoveryToken(to: peerID)
            }
        }
    }
    
    // MARK: - NISession 管理方法
    private func createNISession(for peerID: MCPeerID) -> NISession {
        if let existingSession = niSessions[peerID] {
            return existingSession
        }
        
        let session = NISession()
        session.delegate = self
        niSessions[peerID] = session
        print("🔧 為 \(peerID.displayName) 建立新的 NISession")
        return session
    }
    
    private func removeNISession(for peerID: MCPeerID) {
        if let session = niSessions[peerID] {
            session.invalidate()
            niSessions.removeValue(forKey: peerID)
            print("🧹 移除 \(peerID.displayName) 的 NISession")
        }
        
        // 清理 token 映射
        tokenMap = tokenMap.filter { $0.value != peerID }
    }
    
    private func sendDiscoveryToken(to peerID: MCPeerID) {
        // 確保有對應的 NISession
        let session = createNISession(for: peerID)
        
        guard let token = session.discoveryToken else {
            print("無法獲取 \(peerID.displayName) 的 NIDiscoveryToken，稍後重試")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.sendDiscoveryToken(to: peerID)
            }
            return
        }
        
        // 發送 token
        mcService.sendDiscoveryToken(token, to: peerID)
        print("✅ 發送 discovery token 給 \(peerID.displayName)")
    }
    
    private func handleReceivedToken(from peerID: MCPeerID, token: NIDiscoveryToken) {
        print("📨 收到來自 \(peerID.displayName) 的 discovery token")
        
        // 建立 token 映射
        tokenMap[token] = peerID
        
        // 獲取或建立對應的 NISession
        let session = createNISession(for: peerID)
        
        // 配置並啟動 NI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let config = NINearbyPeerConfiguration(peerToken: token)
            session.run(config)
            print("✅ 已為 \(peerID.displayName) 配置並啟動 NI")
        }
    }
    
    private func handleMCConnectionsUpdate(_ peers: Set<MCPeerID>) {
        DispatchQueue.main.async {
            // 移除已斷線的裝置
            let disconnectedPeers = Set(self.nearbyDevices.keys).subtracting(peers)
            for peerID in disconnectedPeers {
                self.nearbyDevices.removeValue(forKey: peerID)
                self.removeNISession(for: peerID) // 清理對應的 NISession
            }
        }
    }
    
    private func handleMCDiscoveredPeersUpdate(_ peers: Set<MCPeerID>) {
        DispatchQueue.main.async {
            // 為新發現的裝置建立預設的 NearbyDevice 實例
            for peerID in peers {
                if self.nearbyDevices[peerID] == nil {
                    self.nearbyDevices[peerID] = NearbyDevice(
                        id: peerID,
                        displayName: peerID.displayName
                    )
                }
            }
        }
    }

    // MARK: - 公開方法
    func start() {
        if isUnsupportedDevice {
            print("無法啟動：UWB 不支援於此裝置")
            return
        }
        
        print("NearbyInteractionManager 啟動")
        mcService.start()
    }

    func stop() {
        print("NearbyInteractionManager 停止")
        mcService.stop()
        
        // 清理所有 NISession
        niSessions.values.forEach { $0.invalidate() }
        niSessions.removeAll()
        tokenMap.removeAll()
        
        DispatchQueue.main.async {
            self.nearbyDevices.removeAll()
        }
    }

    // MARK: - 更新裝置資訊
    private func updateDevice(_ peerID: MCPeerID, distance: Float?, direction: simd_float3?) {
        // 確保裝置存在或創建新的
        if var existingDevice = self.nearbyDevices[peerID] {
            // 更新現有裝置的資訊
            existingDevice.distance = distance
            existingDevice.direction = direction
            existingDevice.lastUpdateTime = Date()
            self.nearbyDevices[peerID] = existingDevice
        } else {
            // 創建新的 NearbyDevice 實例
            let newDevice = NearbyDevice(
                id: peerID,
                displayName: peerID.displayName,
                distance: distance,
                direction: direction,
                lastUpdateTime: Date()
            )
            self.nearbyDevices[peerID] = newDevice
            print("創建新裝置: \(peerID.displayName)")
        }
    }

    /// 定期清理長時間未更新的裝置
    func cleanupInactiveDevices(timeout: TimeInterval = 30.0) {
        DispatchQueue.main.async {
            let now = Date()
            let inactiveDeviceIDs = self.nearbyDevices.filter { 
                now.timeIntervalSince($0.value.lastUpdateTime) > timeout 
            }.map { $0.key }
            
            for id in inactiveDeviceIDs {
                print("清理超時裝置: \(self.nearbyDevices[id]?.displayName ?? id.displayName)")
                self.nearbyDevices.removeValue(forKey: id)
                self.mcService.disconnectPeer(id)
                self.removeNISession(for: id)
            }
        }
    }
}

// MARK: - NISessionDelegate
extension NearbyInteractionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            guard let peerID = tokenMap[object.discoveryToken] else { continue }
            
            DispatchQueue.main.async {
                self.updateDevice(peerID, distance: object.distance, direction: object.direction)
            }
        }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        for object in nearbyObjects {
            guard let peerID = tokenMap[object.discoveryToken] else { continue }
            
            DispatchQueue.main.async {
                print("📍 移除 \(peerID.displayName) 的距離資料，原因: \(reason)")
                self.updateDevice(peerID, distance: nil, direction: nil)
                // 注意：不要在這裡移除 tokenMap，因為可能只是暫時失去測距
            }
        }
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("❌ NI Session 失效: \(error)")
        
        // 找出是哪個 peer 的 session
        if let peerID = niSessions.first(where: { $0.value == session })?.key {
            DispatchQueue.main.async {
                self.isNISessionInvalidated = true
                self.removeNISession(for: peerID)
                print("🧹 已移除失效的 NISession: \(peerID.displayName)")
            }
        }
    }
}
