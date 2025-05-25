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


/// UWB 和多點連接管理器 (ViewModel)
class NearbyInteractionManager: NSObject, ObservableObject {
    // MARK: - Published 屬性 (UI 會監聽這些變化)
    @Published var nearbyDevices: [MCPeerID: NearbyDevice] = [:] // 儲存偵測到的裝置資訊
    @Published var localDeviceName: String = UIDevice.current.name // 本機裝置名稱
    @Published var isNISessionInvalidated = false // NI Session 是否失效
    @Published var isUnsupportedDevice = false // 是否為不支援 UWB 的裝置

    // MARK: - 服務組件
    private let niService: NIService
    private let mcService: MCService
    
    // MARK: - 其他內部屬性
    private var cancellables = Set<AnyCancellable>() // 用於 Combine

    // MARK: - 初始化
    override init() {
        // 檢查裝置是否支援 UWB
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            print("UWB 不支援於此裝置")
            self.isUnsupportedDevice = true
            // 即使 UWB 不支援，也要初始化服務以避免崩潰
            self.niService = NIService()
            self.mcService = MCService()
            super.init()
            return
        }

        self.mcService = MCService()
        self.niService = NIService()
        
        super.init()
        setupBindings()
 
    }

    deinit {
        stop()
        print("NearbyInteractionManager 已釋放")
    }

    // MARK: - 私有方法
    private func setupBindings() {
        // 監聽 NI 服務的裝置更新
        niService.$nearbyObjects
            .sink { [weak self] objects in
                self?.handleNIObjectsUpdate(objects)
            }
            .store(in: &cancellables)
        
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
        
        // 監聽 NI Session 狀態
        niService.$isSessionInvalidated
            .assign(to: \.isNISessionInvalidated, on: self)
            .store(in: &cancellables)
        
        // 設置 MC 服務的 Discovery Token 回調
        mcService.onDiscoveryTokenReceived = { [weak self] peerID, token in
            self?.niService.runConfiguration(for: peerID, with: token)
        }
        
        // 設置 MC 服務的連接回調，觸發 Discovery Token 發送
        mcService.onPeerConnected = { [weak self] in
            // 延遲發送，確保連接穩定後再發送 Discovery Token
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.niService.sendDiscoveryTokenIfReady()
            }
        }
        
        // 設置 NI 服務的 Discovery Token 發送回調
        niService.onDiscoveryTokenReady = { [weak self] (token: NIDiscoveryToken) in
            self?.mcService.sendDiscoveryToken(token)
        }
    }
    
    private func handleNIObjectsUpdate(_ objects: [MCPeerID: NINearbyObject]) {
        DispatchQueue.main.async {
            for (peerID, object) in objects {
                self.updateDevice(peerID, distance: object.distance, direction: object.direction)
            }
        }
    }
    
    private func handleMCConnectionsUpdate(_ peers: Set<MCPeerID>) {
        DispatchQueue.main.async {
            // 移除已斷線的裝置
            let disconnectedPeers = Set(self.nearbyDevices.keys).subtracting(peers)
            for peerID in disconnectedPeers {
                self.nearbyDevices.removeValue(forKey: peerID)
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
        
        debuglog("NearbyInteractionManager 啟動")
        mcService.start()
        niService.start()
    }

    func stop() {
        print("NearbyInteractionManager 停止")
        niService.stop()
        mcService.stop()
        
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
            debuglog("創建新裝置")
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
                debuglog("清理超時裝置: \(self.nearbyDevices[id]?.displayName ?? id.displayName)")
                self.nearbyDevices.removeValue(forKey: id)
                self.mcService.disconnectPeer(id)
                self.niService.removePeer(id)
            }
        }
    }
}
