import Foundation
import NearbyInteraction // UWB交互
import MultipeerConnectivity // 多設備通信
import UserNotifications // 通知

// 卡爾曼濾注器類別
class KalmanFilter {
    private var estimated: Float = 0.0
    private var uncertainty: Float = 1.0
    private let processNoise: Float
    private let measurementNoise: Float

    init(processNoise: Float = 0.1, measurementNoise: Float = 0.2) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    func update(measurement: Float) -> Float {
        uncertainty += processNoise
        let kalmanGain = uncertainty / (uncertainty + measurementNoise)
        estimated += kalmanGain * (measurement - estimated)
        uncertainty *= (1 - kalmanGain)
        return estimated
    }
}

// NearbyInteractionManager
class NearbyInteractionManager: NSObject, ObservableObject {

    @Published var distance: Float? // 距離
    @Published var direction: simd_float3? // 方向向量
    @Published var smoothAngle: Float? // 平滑角度
    @Published var nearbyDevices: [NINearbyObject] = [] // 附近的設備
    @Published var isChatOpen = false

    private var session: NISession?
    private let mcService = "ni-demo"
    private let mcPeerID = MCPeerID(displayName: UIDevice.current.name) // 當前設備的識別 ID
    private let mcSession: MCSession // 與其他設備交換消息的 P2P 會談
    private let mcAdvertiser: MCNearbyServiceAdvertiser // 廣播本設備
    private let mcBrowser: MCNearbyServiceBrowser  // 掃描並發現其他正在廣播的設備
    private var peerToken: NIDiscoveryToken?
    private var isAdvertising = false // 確保 setupMultipeerConnectivity 只執行一次

    private var distanceFilter = KalmanFilter(processNoise: 0.1, measurementNoise: 0.2)
    private var directionFilterX = KalmanFilter(processNoise: 0.01, measurementNoise: 0.3)
    private var directionFilterY = KalmanFilter(processNoise: 0.01, measurementNoise: 0.3)
    private var directionFilterZ = KalmanFilter(processNoise: 0.01, measurementNoise: 0.3)
    private var angleFilter = KalmanFilter(processNoise: 0.01, measurementNoise: 0.1)

    override init() {
        mcSession = MCSession(peer: mcPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: mcPeerID, discoveryInfo: nil, serviceType: mcService)
        mcBrowser = MCNearbyServiceBrowser(peer: mcPeerID, serviceType: mcService)
        super.init()

        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcBrowser.delegate = self
    }

    // 啟動廣播與搜尋 讓此設備成為"主持人"
    func setupMultipeerConnectivity() {
        guard !isAdvertising else {
            print("正在廣播和搜尋，無需重複啟動")
            return
        }

        isAdvertising = true
        
        mcAdvertiser.startAdvertisingPeer()
        mcBrowser.startBrowsingForPeers()
        print("正在廣播和搜尋設備")
    }

    // 重啟 UWB 會談
    func startSession() {
        if session == nil {
            print("NISession 未初始化，創建一個新的 NISession")
            self.session = NISession()
            self.session?.delegate = self
            return
        }

        if (mcSession.connectedPeers.isEmpty) {
            print("沒有連接的對等設備，等待其他設備")
            return
        }
    }

    //didUpdate 當附近的設備信息更新時调用
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }

        DispatchQueue.main.async {
            if let newDistance = nearbyObject.distance {
                if let currentDistance = self.distance {
                    let maxAllowedChange = 0.5 * currentDistance
                    let difference = abs(currentDistance - newDistance)
                    
                    if difference > maxAllowedChange {
                        print("距離變化過大，進行平滑更新")
                        // 漸進更新 (更新部分差值)
                        self.distance = self.distance! + 0.3 * (newDistance - self.distance!)
                    } else {
                        // 正常更新
                        self.distance = self.distanceFilter.update(measurement: newDistance)
                    }
                } else {
                    // 初次更新
                    self.distance = self.distanceFilter.update(measurement: newDistance)
                }
            }

            if let newDirection = nearbyObject.direction {
                let smoothX = self.directionFilterX.update(measurement: newDirection.x)
                let smoothY = self.directionFilterY.update(measurement: newDirection.y)
                let smoothZ = self.directionFilterZ.update(measurement: newDirection.z)
                print("方向: \(newDirection.x), \(newDirection.y), \(newDirection.z)")
                print("平滑方向: \(smoothX), \(smoothY), \(smoothZ)")
                self.direction = simd_float3(x: smoothX, y: smoothY, z: smoothZ)
                
                // 計算角度
                let rawAngle = -atan2(Double(smoothX), Double(smoothZ)) * 180 / .pi + 180
                let angle = Float((rawAngle > 180) ? rawAngle - 360 : rawAngle)
                
                // 以下在計算完 angle 後插入
                if let oldAngle = self.smoothAngle {
                    let diff = abs(angle - oldAngle)
                    let threshold: Float = 3.0
                    if diff > threshold {
                        // 僅更新部分差值
                        self.smoothAngle = oldAngle + 0.1 * (angle - oldAngle)
                    } else {
                        // 正常更新
                        self.smoothAngle = self.angleFilter.update(measurement: angle)

                    }
                } else {
                    // 初始設定
                    self.smoothAngle = self.angleFilter.update(measurement: angle)

                }
                print("角度: \(angle)")
            }

            self.nearbyDevices = nearbyObjects
        }   
    }

    
    //發送iscovery Token到已知設備
    private func sendTokenToPeers(token: NIDiscoveryToken) {
        guard !mcSession.connectedPeers.isEmpty else {
            print("無可用的連線")
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)

            for peer in mcSession.connectedPeers {
                try mcSession.send(data, toPeers: [peer], with: .reliable)
                print("已向 \(peer.displayName) 發送 Discovery Token")
            }
        } catch {
            print("發送 Discovery Token 失敗: \(error.localizedDescription)")
        }
    }
    
    
    //接收來自 P2P 設備的 Discovery Token
    private func receiveTokenFromPeer(data: Data) {
        do {
            guard let receivedToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
                print("接收的 Token 無效")
                return
            }
            peerToken = receivedToken
            
            guard let session = session else {
                        print("NISession 未初始化")
                        return
                    }
            
            let configuration = NINearbyPeerConfiguration(peerToken: receivedToken)
            configuration.isCameraAssistanceEnabled = false
            
            session.run(configuration)
            print("已配置 Nearby Interaction")
        } catch {
            print("解碼 Token 時出錯: \(error.localizedDescription)")
        }
    }

    func sendChatRequest() {
        guard !mcSession.connectedPeers.isEmpty else { return }
        do {
            let message = "CHAT_REQUEST"
            let data = Data(message.utf8)
            try mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
            print("已發送聊天室請求")
        } catch {
            print("發送訊息失敗: \(error.localizedDescription)")
        }
    }
}


// 平滑指向角度
// extension NearbyInteractionManager {
//     func smoothDirection(current: simd_float3, previous: simd_float3?, smoothingFactor: Float = 0.5) -> simd_float3 {
//         guard let previous = previous else { return current }
//         return simd_float3(
//             x: previous.x * (1 - smoothingFactor) + current.x * smoothingFactor,
//             y: previous.y * (1 - smoothingFactor) + current.y * smoothingFactor,
//             z: previous.z * (1 - smoothingFactor) + current.z * smoothingFactor,
//         )
//     }
// }



extension NearbyInteractionManager: NISessionDelegate {
    //didUpdate 當附近的設備信息（如方向、距離）更新時調用
    // func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
    //     guard let nearbyObject = nearbyObjects.first else { return }
    //     DispatchQueue.main.async {
    //         self.distance = nearbyObject.distance
    //         self.nearbyDevices = nearbyObjects // 更新所有設備的數據
            
    //     if let newDirection = nearbyObject.direction {
    //         self.direction = self.smoothDirection(current: newDirection, previous: self.direction)
    //         } 
    //     else if let previousDirection = self.direction {
    //             self.direction = previousDirection // 維持之前的方向
    //             print("方向數據為 nil，無法更新方向")
    //         }
    //     }
    // }


    // 當會話失效（例如連接丟失）時調用
    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("會話無效，錯誤: \(error.localizedDescription)")
    }

    func sessionWasSuspended(_ session: NISession) {
        print("會話暫停，準備恢復")
        startSession()
    }

    func sessionSuspensionEnded(_ session: NISession) {
        print("會話恢復")
        startSession()
    }
}



extension NearbyInteractionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("\(peerID.displayName) 已連線")
            
            guard let token = self.session?.discoveryToken else {
                        print("無法獲取 Discovery Token")
                        return
                    }
            sendTokenToPeers(token: token)
        case .connecting:
            print("\(peerID.displayName) 連線中...")
        case .notConnected:
            print("\(peerID.displayName) 已斷開")
        @unknown default:
            print("未知狀態")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("收到來自 \(peerID.displayName) 的數據")
        if let message = String(data: data, encoding: .utf8), message == "CHAT_REQUEST" {
            DispatchQueue.main.async {
                self.isChatOpen = true
            }
        }
        receiveTokenFromPeer(data: data) // 解碼
    }

    func session(_: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    func session(_: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
    func session(_: MCSession, didReceive: InputStream, withName: String, fromPeer: MCPeerID) {}
}



// 當接收到來自其他設備的連線請求時，接受該連接
extension NearbyInteractionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("收到來自 \(peerID.displayName) 的連線邀請")
        invitationHandler(true, mcSession)
    }
}



extension NearbyInteractionManager: MCNearbyServiceBrowserDelegate {
    //發現附近的 P2P 設備後，向該設備發送邀請
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("發現設備：\(peerID.displayName)")
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }
    // 當設備離開範圍時，觸發該方法
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("設備離開：\(peerID.displayName)")
    }
}
