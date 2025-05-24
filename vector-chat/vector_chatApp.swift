//
//  UWB_testApp.swift
//  UWB_test
//
//  Created by Saxon on 2024/12/4.
//

import SwiftUI
import NearbyInteraction
import MultipeerConnectivity
import Combine // 用於處理 @Published 屬性的更新


// MARK: - 資料模型

// 表示一個被偵測到的附近裝置
struct NearbyDevice: Identifiable, Equatable {
    let id: MCPeerID // 使用 MCPeerID 作為唯一標識符
    var displayName: String // 裝置的顯示名稱
    var distance: Float? // 距離（公尺）
    var direction: simd_float3? // 方向向量
    var lastUpdateTime: Date = Date() // 最後更新時間，用於清理長時間未更新的裝置

    // 為了在視圖中定位，計算相對於中心點的 CGPoint
    var position: CGPoint? {
        guard let distance = distance, let direction = direction else { return nil }
        // 假設方向向量的 x 和 z 分量對應到 2D 平面的 x 和 y
        // 這裡的轉換比例需要根據您的地圖視圖大小進行調整
        let scaleFactor: Float = 50.0 // 1 公尺對應 50 個點
        // UWB 的方向通常是 (x, y, z)，在地圖上我們可能用 x 和 z (或 x 和 y，取決於座標系統定義)
        // 這裡假設 direction.x 是橫向，direction.z 是縱向 (前方)
        // 注意：UWB 的方向向量是相對於本機裝置的。
        // 如果 direction.z 是正數，表示在前方；負數表示在後方。
        // 如果 direction.x 是正數，表示在右方；負數表示在左方。
        // 在 SwiftUI 座標中，y 軸向下為正。因此，如果 direction.z 為正 (前方)，在地圖上應該是向上 (y 負方向)。
        return CGPoint(x: CGFloat(direction.x * distance * scaleFactor),
                       y: CGFloat(direction.z * distance * scaleFactor)) // y 軸反轉，因為 UWB Z軸向前，螢幕 Y軸向下
    }

    static func == (lhs: NearbyDevice, rhs: NearbyDevice) -> Bool {
        lhs.id == rhs.id && 
        lhs.distance == rhs.distance && 
        lhs.direction == rhs.direction &&
        lhs.displayName == rhs.displayName
    }
}

// MARK: - UWB 和多點連接管理器 (ViewModel)

class NearbyInteractionManager: NSObject, ObservableObject {
    // MARK: - Published 屬性 (UI 會監聽這些變化)
    @Published var nearbyDevices: [MCPeerID: NearbyDevice] = [:] // 儲存偵測到的裝置資訊
    @Published var localDeviceName: String = UIDevice.current.name // 本機裝置名稱
    @Published var isNISessionInvalidated = false // NI Session 是否失效
    @Published var isUnsupportedDevice = false // 是否為不支援 UWB 的裝置

    // MARK: - NearbyInteraction 相關屬性
    var niSession: NISession? // 改為 internal 存取權限
    private var sessionInvalidated = false // 內部追蹤 NI Session 狀態

    // MARK: - MultipeerConnectivity 相關屬性
    private let serviceType = "vectorchat" // 自定義服務類型，兩台裝置需一致
    private var myPeerID: MCPeerID
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private var serviceBrowser: MCNearbyServiceBrowser
    private var connectedPeers: [MCPeerID: MCSession] = [:] // 儲存已連接的 peer 和對應的 session
    private var activeSessions: [MCSession] = [] // 儲存所有活動的 session
    private var sessionToPeers: [MCSession: MCPeerID] = [:] // session 到 peer 的映射

    // MARK: - 其他內部屬性
    private var discoveryTokenToPeerMap: [NIDiscoveryToken: MCPeerID] = [:] // 儲存 discovery token 和 peerID 的對應
    private var peerIDToDiscoveryTokenMap: [MCPeerID: NIDiscoveryToken] = [:] // 儲存 peerID 和 discovery token 的對應
    private var cancellables = Set<AnyCancellable>() // 用於 Combine
    private let deviceUUID: String // 裝置的唯一識別碼
    private var pendingInvitations: Set<MCPeerID> = [] // 追蹤等待中的邀請
    private var connectingPeers: Set<MCPeerID> = [] // 追蹤正在嘗試連接的裝置

    // MARK: - 初始化
    override init() {
        // 獲取裝置的唯一識別碼
        self.deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        // 檢查裝置是否支援 UWB
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            print("UWB 不支援於此裝置")
            self.isUnsupportedDevice = true
            // 初始化 MultipeerConnectivity 相關的屬性，即使 UWB 不支援，也需要先初始化
            self.myPeerID = MCPeerID(displayName: deviceUUID)
            self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["uuid": deviceUUID], serviceType: serviceType)
            self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            super.init() // 調用父類初始化
            return
        }

        self.myPeerID = MCPeerID(displayName: deviceUUID) // 使用裝置名稱作為 PeerID

        // 初始化服務廣播器，加入 UUID 資訊
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["uuid": deviceUUID], serviceType: serviceType)
        // 初始化服務瀏覽器
        self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)

        super.init()

        // 設定 MultipeerConnectivity 的代理
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self

        debuglog("本機 PeerID: \(myPeerID.displayName.prefix(5))")
        startBrowse() // 開始瀏覽附近裝置
        startAdvertising() // 開始廣播本機服務

        // 初始化並啟動 NearbyInteraction Session
        setupNISession()
    }

    deinit {
        stopNISession()
        stopBrowse()
        stopAdvertising()
        print("NearbyInteractionManager 已釋放")
    }

    // MARK: - 公開方法
    func start() {
        if isUnsupportedDevice {
            print("無法啟動：UWB 不支援於此裝置")
            return
        }
        debuglog("NearbyInteractionManager 啟動")
        startBrowse()
        startAdvertising()
        if niSession == nil {
            setupNISession() // 如果 session 尚未建立，則建立它
        }
    }

    func stop() {
        print("NearbyInteractionManager 停止")
        stopNISession()
        stopBrowse()
        stopAdvertising()
        // 清理所有已連接的 peers 和裝置資訊
        DispatchQueue.main.async {
            self.nearbyDevices.removeAll()
            self.connectedPeers.values.forEach { $0.disconnect() }
            self.connectedPeers.removeAll()
            self.discoveryTokenToPeerMap.removeAll()
            self.peerIDToDiscoveryTokenMap.removeAll()
        }
    }

    // MARK: - NearbyInteraction Session 設定與管理
    private func setupNISession() {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            print("UWB 不支援於此裝置，無法設定 NI Session")
            self.isUnsupportedDevice = true
            return
        }

        // 避免重複創建 Session
        guard niSession == nil else {
            debuglog("NI Session 已經存在")
            return
        }

        niSession = NISession()
        niSession?.delegate = self
        sessionInvalidated = false
        isNISessionInvalidated = false
        debuglog("NI Session 已設定並指派代理")

        // 監聽應用程式生命週期事件，以處理 session 失效
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                print("App 進入背景，NI Session 可能會失效")
                // 根據 Apple 建議，進入背景時可以選擇性地暫停 session，或讓其自然失效
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                print("App 返回前景，檢查 NI Session 狀態")
                if let self = self, self.sessionInvalidated { // 如果之前已標記為失效
                    print("NI Session 已失效，重新設定")
                    self.setupNISession() // 嘗試重新設定
                } else if self?.niSession == nil && NISession.deviceCapabilities.supportsPreciseDistanceMeasurement {
                    print("NI Session 為 nil，重新設定")
                    self?.setupNISession()
                }
            }
            .store(in: &cancellables)
    }

    private func stopNISession() {
        niSession?.invalidate()
        niSession = nil
        sessionInvalidated = true
        isNISessionInvalidated = true
        print("NI Session 已停止並失效")
    }

    // MARK: - MultipeerConnectivity 服務廣播與瀏覽
    private func startAdvertising() {
        serviceAdvertiser.startAdvertisingPeer()
        debuglog("開始廣播服務: \(serviceType)")
    }

    private func stopAdvertising() {
        serviceAdvertiser.stopAdvertisingPeer()
        print("停止廣播服務")
    }

    private func startBrowse() {
        serviceBrowser.startBrowsingForPeers()
        debuglog("開始瀏覽附近裝置: \(serviceType)")
    }

    private func stopBrowse() {
        serviceBrowser.stopBrowsingForPeers()
        print("停止瀏覽附近裝置")
    }

    // MARK: - 資料交換 (Discovery Token)
    // 當 MultipeerConnectivity 連接建立後，發送本機的 Discovery Token
    private func sendDiscoveryToken(to peerID: MCPeerID, session: MCSession) {
        guard let token = niSession?.discoveryToken else {
            debuglog("無法獲取本機 NI Discovery Token")
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try session.send(data, toPeers: [peerID], with: .reliable)
            debuglog("已傳送 Discovery Token 給 \(peerID.displayName)")
            // 儲存已傳送 token 的 peer，避免重複執行 NI Session run
            peerIDToDiscoveryTokenMap[peerID] = token // 這裡儲存的是自己的 token，用於辨識是哪個 peer
        } catch {
            debuglog("傳送 Discovery Token 失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - 更新裝置資訊
    private func updateDevice(_ peerID: MCPeerID, distance: Float?, direction: simd_float3?) {
        DispatchQueue.main.async {
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
    }

    // 定期清理長時間未更新的裝置 (可選)
    func cleanupInactiveDevices(timeout: TimeInterval = 30.0) {
        DispatchQueue.main.async {
            let now = Date()
            let inactiveDeviceIDs = self.nearbyDevices.filter { now.timeIntervalSince($0.value.lastUpdateTime) > timeout }.map { $0.key }
            for id in inactiveDeviceIDs {
                debuglog("清理超時裝置: \(self.nearbyDevices[id]?.displayName ?? id.displayName)")
                self.nearbyDevices.removeValue(forKey: id)
                // 也考慮斷開 MPC 連接或停止 NI session for this peer
                if let session = self.connectedPeers[id] {
                    session.disconnect()
                    self.connectedPeers.removeValue(forKey: id)
                }
                if let token = self.peerIDToDiscoveryTokenMap[id] {
                    // 如果有針對這個 peer 的 NI session config，理論上應該在 NI session delegate 中處理移除
                    // 但這裡可以做一個輔助清理
                    self.peerIDToDiscoveryTokenMap.removeValue(forKey: id)
                    // 如果 tokenToPeerMap 也用了這個 token，也應該清理
                    let tokensToRemove = self.discoveryTokenToPeerMap.filter { $0.value == id }.map { $0.key }
                    for t in tokensToRemove {
                        self.discoveryTokenToPeerMap.removeValue(forKey: t)
                    }
                }
            }
        }
    }
}



// MARK: - NISessionDelegate 擴展
extension NearbyInteractionManager: NISessionDelegate {
    // 當 NI Session 更新附近物件時調用
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        debuglog("NI Session 收到更新，物件數量: \(nearbyObjects.count)")
        for object in nearbyObjects {
            guard let peerID = discoveryTokenToPeerMap[object.discoveryToken] else {
                debuglog("收到未知 Discovery Token 的更新: \(object.discoveryToken)")
                continue
            }
            // print("NI Session 更新: \(peerID.displayName), 距離: \(object.distance ?? -1), 方向: \(object.direction?.debugDescription ?? "N/A")")
            updateDevice(peerID, distance: object.distance, direction: object.direction)
        }
    }

    // 當 NI Session 移除附近物件時調用 (例如超出範圍)
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        for object in nearbyObjects {
            guard let peerID = discoveryTokenToPeerMap[object.discoveryToken] else {
                debuglog("收到未知 Discovery Token 的移除通知: \(object.discoveryToken)")
                continue
            }
            debuglog("NI Session 移除了裝置: \(peerID.displayName), 原因: \(reason.description)")
            DispatchQueue.main.async {
                self.nearbyDevices.removeValue(forKey: peerID)
                self.discoveryTokenToPeerMap.removeValue(forKey: object.discoveryToken)
                self.peerIDToDiscoveryTokenMap.removeValue(forKey: peerID)
            }
            // 根據移除原因決定是否需要重新嘗試連接或做其他處理
            switch reason {
            case .peerEnded:
                print("  原因: 對方結束了 Session")
                // 對方可能關閉了 App 或 UWB 功能
            case .timeout:
                print("  原因: 連接超時")
                // 可能需要重新掃描或提示用戶
            @unknown default:
                print("  原因: 未知")
            }
        }
    }

    // 當 NI Session 因錯誤而失效時調用
    func sessionWasSuspended(_ session: NISession) {
        print("NI Session 已暫停 (Was Suspended)")
        // 通常發生在 App 進入背景
    }

    func sessionSuspensionEnded(_ session: NISession) {
        debuglog("NI Session 暫停結束 (Suspension Ended)")
        // App 返回前景，可以嘗試重新運行 session
        // 這裡可以檢查 connectedPeers 並為它們重新 run configuration
        // 但通常在 App 返回前景時，會重新檢查並設定 session
        debuglog("嘗試為已連接的 Peers 重新運行 NI Configuration")
        for (peerID, token) in peerIDToDiscoveryTokenMap {
            if connectedPeers[peerID] != nil { // 確保 MPC 仍然連接
                let config = NINearbyPeerConfiguration(peerToken: token)
                debuglog("  為 \(peerID.displayName) 重新運行 NI Configuration")
                niSession?.run(config)
            }
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        debuglog("NI Session 失效: \(error.localizedDescription)")
        sessionInvalidated = true
        isNISessionInvalidated = true // 更新 Published 屬性
        // 根據錯誤類型處理，例如：
        // - NIError.Code.userDidNotAllow: 用戶未授權
        // - NIError.Code.invalidConfiguration: 設定錯誤
        // - NIError.Code.sessionFailed: Session 內部錯誤
        // 可以嘗試重新啟動 Session，或者提示用戶
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // 避免立即重試導致循環
            if NISession.deviceCapabilities.supportsPreciseDistanceMeasurement && !(self?.isUnsupportedDevice ?? true) { // 確保仍然支援且不是因為不支援而失效
                 debuglog("嘗試重新設定 NI Session...")
                 self?.setupNISession() // 嘗試重新設定
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate 擴展
extension NearbyInteractionManager: MCNearbyServiceAdvertiserDelegate {
    // 收到連接邀請時調用
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        debuglog("收到來自 \(peerID.displayName) 的連接邀請")

        // 檢查是否已經與此 peer 連接
        if let existingSession = connectedPeers[peerID], existingSession.connectedPeers.contains(peerID) {
            debuglog("與 \(peerID.displayName) 已經建立連接，拒絕邀請")
            invitationHandler(false, nil)
            return
        }

        // 檢查是否正在等待此 peer 的邀請響應
        if pendingInvitations.contains(peerID) {
            debuglog("接受到 \(peerID.displayName) 的邀請，但本機也有 pending invite，接受對方優先")
            pendingInvitations.remove(peerID)
            
            // 如果有現有的 session 在嘗試連接，先斷開
            if let existingSession = connectedPeers[peerID] {
                existingSession.disconnect()
                // 從 activeSessions 和 sessionToPeers 中移除
                if let index = activeSessions.firstIndex(of: existingSession) {
                    activeSessions.remove(at: index)
                }
                sessionToPeers.removeValue(forKey: existingSession)
            }
        }

        // 為每個邀請創建新的獨立 session
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // 將新 session 加入管理
        activeSessions.append(session)
        sessionToPeers[session] = peerID
        connectedPeers[peerID] = session // 儲存 session
        
        invitationHandler(true, session)
        debuglog("已接受來自 \(peerID.displayName) 的連接邀請，並建立獨立 MCSession")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        debuglog("服務廣播啟動失敗: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate 擴展
extension NearbyInteractionManager: MCNearbyServiceBrowserDelegate {
    // 發現附近裝置時調用
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        debuglog("發現裝置: \(peerID.displayName)")

        // 檢查是否已連接或正在連接
        guard connectedPeers[peerID] == nil && !connectingPeers.contains(peerID) else {
            debuglog("裝置 \(peerID.displayName) 已連接或正在連接，忽略此次發現。")
            return
        }

        // 檢查是否已有等待中的邀請
        guard !pendingInvitations.contains(peerID) else {
            debuglog("已存在等待中的邀請給 \(peerID.displayName)，跳過")
            return
        }

        // 使用 UUID 來決定誰發送邀請
        // 如果本機 UUID 字典序小於對方 UUID，則發送邀請
        if let peerUUID = info?["uuid"], deviceUUID < peerUUID {
            debuglog("本機 UUID 字典序較小，發送邀請給 \(peerID.displayName)")
            
            // 為每個 peer 創建獨立的 session
            let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            
            // 將 session 加入管理
            activeSessions.append(session)
            sessionToPeers[session] = peerID
            connectedPeers[peerID] = session // 先儲存，即使邀請失敗也知道嘗試過
            pendingInvitations.insert(peerID) // 記錄等待中的邀請
            connectingPeers.insert(peerID) // 標記為正在連接
            
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30) // 30 秒超時
            debuglog("已向 \(peerID.displayName) 發送連接邀請")
        } else {
            debuglog("本機 UUID 字典序較大或無法比較，等待對方邀請 \(peerID.displayName)")
        }

        // 預先創建一個 NearbyDevice 實例，即使 MPC 連接後才會有 UWB 數據
        DispatchQueue.main.async {
            if self.nearbyDevices[peerID] == nil {
                 self.nearbyDevices[peerID] = NearbyDevice(id: peerID, displayName: peerID.displayName)
            }
        }
    }

    // 附近裝置消失時調用
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        debuglog("裝置消失 (MPC): \(peerID.displayName)")
        DispatchQueue.main.async {
            // MPC lostPeer 不一定代表 UWB 連接斷開，但可以作為一個清理的觸發點
            // UWB 的移除由 NISessionDelegate 的 didRemove 處理更為精確
            // 但如果 MPC 連接斷了，UWB 也無法交換 token
            if let session = self.connectedPeers[peerID] {
                session.disconnect()
                self.connectedPeers.removeValue(forKey: peerID)
            }
            // 可以選擇性地從 nearbyDevices 移除，或者等待 UWB timeout
            // self.nearbyDevices.removeValue(forKey: peerID) // 立即移除，UI上會消失
            // self.peerIDToDiscoveryTokenMap.removeValue(forKey: peerID)
            // 清理 discoveryTokenToPeerMap 中對應的 token
            // let tokensToRemove = self.discoveryTokenToPeerMap.filter { $0.value == peerID }.map { $0.key }
            // for token in tokensToRemove {
            //     self.discoveryTokenToPeerMap.removeValue(forKey: token)
            // }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowseForPeers error: Error) {
        debuglog("裝置瀏覽啟動失敗: \(error.localizedDescription)")
    }
}

// MARK: - MCSessionDelegate 擴展
extension NearbyInteractionManager: MCSessionDelegate {
    // 當連接狀態改變時調用
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { // 確保在主線程更新 UI 相關數據
            switch state {
            case .connected:
                debuglog("MPC Session 與 \(peerID.displayName) 已連接")
                self.connectedPeers[peerID] = session // 確認 session 已儲存
                self.pendingInvitations.remove(peerID) // 移除等待中的邀請狀態
                self.connectingPeers.remove(peerID) // 移除正在連接的狀態
                // 連接成功後，發送本機的 Discovery Token
                self.sendDiscoveryToken(to: peerID, session: session)
                // 同時，如果之前有這個 peer 的 NearbyDevice 但沒有 UWB 數據，現在可以期待 UWB 數據了
                if self.nearbyDevices[peerID] == nil {
                    self.nearbyDevices[peerID] = NearbyDevice(id: peerID, displayName: peerID.displayName)
                }

            case .connecting:
                debuglog("MPC Session 與 \(peerID.displayName) 正在連接...")
            case .notConnected:
                debuglog("MPC Session 與 \(peerID.displayName) 未連接或已斷開")
                self.connectedPeers.removeValue(forKey: peerID)
                self.pendingInvitations.remove(peerID) // 移除等待中的邀請狀態
                self.connectingPeers.remove(peerID) // 移除正在連接的狀態
                // 當 MPC 斷開時，也應該清理 NI 相關的資訊，因為無法再交換數據
                // UWB session for this peer will eventually timeout or be removed via didRemove.
                // 但我們可以主動清理 UI
                if self.nearbyDevices[peerID] != nil {
                    print("  由於 MPC 斷開，從 nearbyDevices 移除 \(peerID.displayName)")
                    self.nearbyDevices.removeValue(forKey: peerID)
                }
                if let token = self.peerIDToDiscoveryTokenMap.removeValue(forKey: peerID) {
                    // 清理 discoveryTokenToPeerMap 中對應的 token
                    let tokensToRemove = self.discoveryTokenToPeerMap.filter { $0.key == token }.map { $0.key }
                    for t in tokensToRemove {
                        self.discoveryTokenToPeerMap.removeValue(forKey: t)
                    }
                }
                 print("  清理 \(peerID.displayName) 的 MPC 和 NI 關聯數據")
            @unknown default:
                print("MPC Session 與 \(peerID.displayName) 狀態未知")
            }
        }
    }

    // 收到對方傳來的資料時調用 (這裡用來接收 Discovery Token)
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        debuglog("從 \(peerID.displayName) 收到資料，長度: \(data.count)")
        do {
            // 嘗試解碼收到的資料為 NIDiscoveryToken
            if let discoveryToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
                debuglog("成功從 \(peerID.displayName) 收到 Discovery Token: \(discoveryToken)") //discoveryToken 為對方token

                // 儲存對方 token 和 peerID 的對應關係
                self.discoveryTokenToPeerMap[discoveryToken] = peerID
                // 也儲存 peerID 和對方 token 的關係，方便後續使用
                self.peerIDToDiscoveryTokenMap[peerID] = discoveryToken // 這裡存的是對方的 token

                // 使用收到的 Discovery Token 設定並運行 NI Peer Configuration
                // 確保 niSession 存在且有效
                guard let niSession = self.niSession, !self.sessionInvalidated else {
                    debuglog("NI Session 無效或不存在，無法為 \(peerID.displayName) 運行 Configuration")
                    if NISession.deviceCapabilities.supportsPreciseDistanceMeasurement {
                        print("嘗試重新設定 NI Session 後再處理 Token...")
                        self.setupNISession() // 嘗試重新設定
                        // 延遲一點時間再嘗試 run configuration，給 setupNISession 一點時間
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if let validSession = self.niSession, !self.sessionInvalidated {
                                let config = NINearbyPeerConfiguration(peerToken: discoveryToken)
                                print("(延遲後) 為 \(peerID.displayName) 運行 NI Configuration")
                                validSession.run(config)
                            } else {
                                print("(延遲後) NI Session 仍然無效，無法為 \(peerID.displayName) 運行 Configuration")
                            }
                        }
                    }
                    return
                }


                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let configuration = NINearbyPeerConfiguration(peerToken: discoveryToken)
                    debuglog("為 \(peerID.displayName) 運行 NI Configuration")
                    niSession.run(configuration)
                }

                // 在 UI 上顯示這個裝置 (即使還沒有距離和方向)
                DispatchQueue.main.async {
                    if self.nearbyDevices[peerID] == nil {
                        self.nearbyDevices[peerID] = NearbyDevice(id: peerID, displayName: peerID.displayName)
                        debuglog("  已將 \(peerID.displayName) 加入 nearbyDevices (等待 UWB 數據)")
                    }
                }
            } else {
                debuglog("從 \(peerID.displayName) 收到的資料無法解碼為 Discovery Token")
                // 這裡可以處理其他類型的數據，例如聊天訊息
            }
        } catch {
            debuglog("處理從 \(peerID.displayName) 收到的資料失敗: \(error.localizedDescription)")
        }
    }

    // 以下 MCSessionDelegate 方法在此範例中未使用，但必須實作
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // 用於接收數據流
        debuglog("MCSession: didReceive stream from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // 開始接收資源 (例如檔案)
        debuglog("MCSession: didStartReceivingResourceWithName \(resourceName) from \(peerID.displayName)")
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // 完成接收資源
        if let error = error {
            print("MCSession: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName) with error: \(error)")
            return
        }
        debuglog("MCSession: didFinishReceivingResourceWithName \(resourceName) from \(peerID.displayName) at \(localURL?.absoluteString ?? "N/A")")
    }
}

// NINearbyObject.RemovalReason 的描述擴展 (方便日誌輸出)
extension NINearbyObject.RemovalReason {
    var description: String {
        switch self {
        case .peerEnded: return "Peer Ended"
        case .timeout: return "Timeout"
        @unknown default: return "Unknown"
        }
    }
}


// MARK: - UI 視圖 (SwiftUI)

// 主視圖，包含雷達和裝置列表
struct ContentView: View {
    @StateObject private var interactionManager = NearbyInteractionManager()
    @State private var showUnsupportedDeviceAlert = false
    @State private var showNISessionInvalidatedAlert = false

    // 雷達視圖的縮放和拖曳狀態
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationView {
            VStack {
                if interactionManager.isUnsupportedDevice {
                    Text("此裝置不支援 UWB (Ultra Wideband)")
                        .foregroundColor(.red)
                        .padding()
                        .onAppear {
                            showUnsupportedDeviceAlert = true
                        }
                } else {
                    Text("本機裝置: \(interactionManager.localDeviceName)")
                        .font(.headline)
                        .padding(.top)

                    // 雷達視圖
                    RadarView(devices: Array(interactionManager.nearbyDevices.values), scale: $scale, offset: $offset)
                        .frame(height: 300) // 給雷達一個固定高度
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(15)
                        .padding()
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale *= delta
                                }
                                .onEnded { value in
                                    lastScale = 1.0
                                }
                        )
                        .simultaneousGesture( // 允許同時拖曳和縮放
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height)
                                }
                                .onEnded { value in
                                    lastOffset = offset
                                }
                        )


                    Text("附近的裝置 (\(interactionManager.nearbyDevices.count))")
                        .font(.title2)
                        .padding(.top)

                    List {
                        ForEach(Array(interactionManager.nearbyDevices.values)) { device in
                            DeviceRow(device: device)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("UWB Nearby Radar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(interactionManager.niSession == nil || interactionManager.isNISessionInvalidated ? "啟動" : "重新整理") {
                        if interactionManager.isNISessionInvalidated || interactionManager.niSession == nil {
                            interactionManager.start()
                        } else {
                            // 簡單的重新整理：停止再開始（會重新廣播和掃描）
                            interactionManager.stop()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // 給一點時間停止
                                interactionManager.start()
                            }
                        }
                    }
                }
            }
            .onAppear {
                interactionManager.start() // App 出現時啟動
                // 可以在這裡設定一個 Timer 來定期清理超時的裝置
                Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
                    interactionManager.cleanupInactiveDevices()
                }
            }
            .onDisappear {
                // interactionManager.stop() // App 消失時停止 (視需求而定，若希望背景運作則不要停止)
            }
            .alert("不支援的裝置", isPresented: $showUnsupportedDeviceAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text("您的 iPhone 型號不支援 UWB (Ultra Wideband) 技術，此 App 的核心定位功能將無法使用。需要 iPhone 11 或更新的型號。")
            }
            .alert("Nearby Interaction Session 失效", isPresented: $showNISessionInvalidatedAlert) {
                Button("重新啟動", role: .destructive) {
                    interactionManager.start() // 嘗試重新啟動
                }
                Button("好", role: .cancel) { }
            } message: {
                Text("與附近裝置的互動 Session 已失效。這可能是因為 App 進入背景、權限問題或其他錯誤。您可以嘗試重新啟動。")
            }
            .onChange(of: interactionManager.isNISessionInvalidated) { newValue in
                if newValue {
                    // 避免在 isUnsupportedDevice 為 true 時也彈出這個警告
                    if !interactionManager.isUnsupportedDevice {
                        showNISessionInvalidatedAlert = true
                    }
                }
            }
        }
    }
}

// 雷達視圖
struct RadarView: View {
    let devices: [NearbyDevice]
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // 雷達背景線 (可選)
                ForEach(0..<4) { i in
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        .frame(width: CGFloat(i + 1) * 50 * scale, height: CGFloat(i + 1) * 50 * scale)
                        .position(x: center.x + offset.width, y: center.y + offset.height)
                }
                 Line() // X 軸
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [5]))
                    .foregroundColor(.blue.opacity(0.5))
                    .frame(height: 1)
                    .position(x: center.x + offset.width, y: center.y + offset.height)
                 Line(isVertical: true) // Y 軸
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [5]))
                    .foregroundColor(.blue.opacity(0.5))
                    .frame(width: 1)
                    .position(x: center.x + offset.width, y: center.y + offset.height)


                // 本機裝置 (中心點)
                Circle()
                    .fill(Color.green)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .position(x: center.x + offset.width, y: center.y + offset.height) // 中心點加上拖曳的偏移

                // 附近裝置
                ForEach(devices) { device in
                    if let position = device.position {
                        DeviceMarkerView(device: device)
                            .position(
                                x: center.x + (position.x * scale) + offset.width,
                                y: center.y + (position.y * scale) + offset.height // y 軸在地圖上是正常的，不需要反轉
                            )
                            .animation(.easeInOut(duration: 0.3), value: device.position) // 位置變化時動畫
                            .animation(.easeInOut(duration: 0.3), value: scale)
                            .animation(.easeInOut(duration: 0.3), value: offset)
                    }
                }
            }
            .clipped() // 超出邊界的視圖不顯示
        }
    }
}

// 雷達圖中的水平線和垂直線
struct Line: Shape {
    var isVertical: Bool = false
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}


// 裝置在雷達上的標記視圖
struct DeviceMarkerView: View {
    let device: NearbyDevice
    @State private var showingActionSheet = false // 控制是否顯示操作選單

    var body: some View {
        VStack {
            Circle()
                .fill(device.distance != nil ? Color.blue : Color.orange) // 有距離方向用藍色，否則橘色 (表示已 MPC 連接但 UWB 未就緒)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                .onTapGesture {
                    print("點擊了裝置: \(device.displayName)")
                    showingActionSheet = true // 點擊時顯示選單
                }
            Text(device.displayName.prefix(3)) // 顯示名稱前綴
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .actionSheet(isPresented: $showingActionSheet) {
            ActionSheet(
                title: Text("操作選項: \(device.displayName)"),
                message: Text(device.distance != nil ? String(format: "距離: %.2f 公尺", device.distance!) : "距離未知"),
                buttons: [
                    .default(Text("發送聊天邀請 (待實作)")) {
                        // TODO: 實作發送聊天邀請的邏輯
                        print("TODO: 向 \(device.displayName) 發送聊天邀請")
                    },
                    .cancel(Text("取消"))
                ]
            )
        }
    }
}


// 列表中的裝置行視圖
struct DeviceRow: View {
    let device: NearbyDevice

    var body: some View {
        HStack {
            Image(systemName: "iphone.gen2.radiowaves.left.and.right") // 使用一個合適的圖標
                .foregroundColor(device.distance != nil && device.direction != nil ? .blue : .orange)
            VStack(alignment: .leading) {
                Text(device.displayName)
                    .font(.headline)
                
                // 調試輸出 - 改進版本
                let _ = debuglog("\(device.displayName.prefix(5)) - distance: \(device.distance?.description ?? "nil"), direction: \(device.direction?.debugDescription ?? "nil"), lastUpdateTime: \(device.lastUpdateTime)")
                
                if let distance = device.distance {
                    Text(String(format: "距離: %.2f 公尺", distance))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("距離: 正在偵測...")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
                if let direction = device.direction {
                    // 簡單顯示方向向量，您可以轉換為更友好的描述 (例如：前方偏左)
                    // 這裡我們用Azimuth (水平方位角) 和 Elevation (俯仰角) 來描述
                    let azimuth = atan2(direction.x, direction.z) // 水平方位角 (弧度)
                    let elevation = asin(direction.y) // 俯仰角 (弧度)
                    Text(String(format: "方位角: %.0f°, 俯仰角: %.0f°", azimuth * 180 / .pi, elevation * 180 / .pi))
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                     Text("方向: 正在偵測...")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            // 可以加上一個指示燈表示 UWB 連接狀態
            Circle()
                .frame(width: 10, height: 10)
                .foregroundColor(device.distance != nil && device.direction != nil ? .green : .yellow)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - App 入口點
@main
struct vector_chatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

///#Preview {
///    ContentView()
///}
