import SwiftUI
import NearbyInteraction // UWB交互
import MultipeerConnectivity // 多設備通信

// ContentView
struct ContentView: View {
    @StateObject private var nearbyInteractionManager = NearbyInteractionManager()

    var body: some View {
        ZStack { // 堆疊視圖
            VStack { // 垂直布局
                Text("Nearby Interaction Demo")
                    .font(.largeTitle)
                    .padding()

                if let distance = nearbyInteractionManager.distance {
                    Text("距離: \(String(format: "%.2f", distance)) 公尺")
                        .font(.headline)
                } else {
                    Text("正在測量距離...")
                        .font(.headline)
                }

                Button(action: {
                    nearbyInteractionManager.startSession()
                }) {
                    Text("重新啟動會話")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 20)
            }
            .padding()

            // 指针视图
            if let direction = nearbyInteractionManager.direction {
                PointerView(direction: direction, distance: nearbyInteractionManager.distance)
            }
        }
        .onAppear {
            nearbyInteractionManager.setupMultipeerConnectivity()
            nearbyInteractionManager.startSession()
        }
    }
}




// NearbyInteractionManager
class NearbyInteractionManager: NSObject, ObservableObject {

    @Published var distance: Float? //距離
    @Published var direction: simd_float3? //方向向量

    private var session: NISession?
    private let mcService = "ni-demo"
    private let mcPeerID = MCPeerID(displayName: UIDevice.current.name) //當前設備的識別 ID，會與其他設備進行 P2P 連接
    private let mcSession: MCSession //與其他設備交換消息的 P2P 會話
    private let mcAdvertiser: MCNearbyServiceAdvertiser //廣播本設備
    private let mcBrowser: MCNearbyServiceBrowser  //掃描並發現其他正在廣播的設備
    private var peerToken: NIDiscoveryToken?

    override init() {
        mcSession = MCSession(peer: mcPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: mcPeerID, discoveryInfo: nil, serviceType: mcService)
        mcBrowser = MCNearbyServiceBrowser(peer: mcPeerID, serviceType: mcService)
        super.init()

        mcSession.delegate = self
        mcAdvertiser.delegate = self
        mcBrowser.delegate = self
    }

    
    //啟動廣播與搜尋 讓此設備成為"主持人"
    func setupMultipeerConnectivity() {
        mcAdvertiser.startAdvertisingPeer()
        mcBrowser.startBrowsingForPeers()
        print("正在廣播和搜尋設備")
    }

    //重啟 UWB 會話
    func startSession() {
        session?.invalidate()
        session = NISession()
        guard let session = session else {
            print("無法初始化 NISession")
            return
        }
        session.delegate = self

        guard let myToken = session.discoveryToken else {
            print("無法獲取本地 Discovery Token")
            return
        }
        
        if mcSession.connectedPeers.isEmpty {
            print("沒有連接的對等設備，等待其他設備")
            return
        }
        
        sendTokenToPeers(token: myToken)
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
}

// 平滑指向角度
extension NearbyInteractionManager {
    func smoothDirection(current: simd_float3, previous: simd_float3?, smoothingFactor: Float = 0.8) -> simd_float3 {
        guard let previous = previous else { return current }
        return simd_float3(
            x: previous.x * (1 - smoothingFactor) + current.x * smoothingFactor,
            y: previous.y * (1 - smoothingFactor) + current.y * smoothingFactor,
            z: previous.z * (1 - smoothingFactor) + current.z * smoothingFactor
        )
    }
}

//
extension NearbyInteractionManager: NISessionDelegate {
    //didUpdate 當附近的設備信息（如方向、距離）更新時調用
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }
        DispatchQueue.main.async {
            self.distance = nearbyObject.distance

            if let newDirection = nearbyObject.direction {
                self.direction = self.smoothDirection(current: newDirection, previous: self.direction)
            }
        }
    }


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


@main
struct NearbyInteractionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//#Preview {
//    ContentView()
//}
