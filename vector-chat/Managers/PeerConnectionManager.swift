import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Combine

final class PeerConnectionManager: NSObject, ObservableObject {
    // MARK: – 公開狀態
    @Published var discoveredPeers: [MCPeerID] = []
    @Published var session: MCSession!
    
    // Combine 發布聊天 / token / 離線等事件
    let receivedToken = PassthroughSubject<(MCPeerID, NIDiscoveryToken), Never>()
    let receivedChat  = PassthroughSubject<(MCPeerID, String), Never>()
    let peerStateChanged = PassthroughSubject<(MCPeerID, Bool), Never>()
    let tokenReceived   = PassthroughSubject<MCPeerID, Never>()

    
    // MARK: – 私有
    private let serviceType: String = "vectorchat"
    private let myPeerID    = MCPeerID(displayName: UIDevice.current.name)
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser:    MCNearbyServiceBrowser!
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
    
    // 發送聊天文字
    func sendChat(_ message: String, to peers: [MCPeerID]) {
        guard !peers.isEmpty,
              let data = message.data(using: .utf8) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }
    
    // 呼叫對方（Radar 圖示點擊後呼叫）
    func invite(_ peer: MCPeerID) {
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }
    
    // 傳送本機 UWB token 給所有已連線 peer
    func broadcast(token: NIDiscoveryToken) {
        // token 需做 NSData 編碼
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token, requiringSecureCoding: true) {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }
}

// MARK: – MCSessionDelegate
extension PeerConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {

        print("[MC] \(peerID.displayName) state = \(state.rawValue)")  //debug // 0=notConn 1=connecting 2=connected 

        DispatchQueue.main.async {
            let connected = (state == .connected)
            self.peerStateChanged.send((peerID, connected))

            switch state {
            case .connected:
                print("\(peerID.displayName) connected")
            case .notConnected:
                print("\(peerID.displayName) disconnected")
            case .connecting:
                break
            @unknown default: break
            }
        }
    }
    
    func session(_ session: MCSession,
                 didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("[MC] didReceive \(data.count) bytes from \(peerID.displayName)") //debug
        // 嘗試解碼 token 或文字
        if let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {

            print("[MC] token received from \(peerID.displayName)") //debug

            receivedToken.send((peerID, token))
            tokenReceived.send(peerID)
        } else if let text = String(data: data, encoding: .utf8) {
            receivedChat.send((peerID, text))
        }
    }
    
    // 其餘 delegate 空實作
    func session(_:MCSession, didReceive _:InputStream, withName _:String, fromPeer _:MCPeerID) {}
    func session(_:MCSession, didStartReceivingResourceWithName _:String, fromPeer _:MCPeerID, with _:Progress) {}
    func session(_:MCSession, didFinishReceivingResourceWithName _:String, fromPeer _:MCPeerID, at _:URL?, withError _:Error?) {}
}

// MARK: – Advertiser & Browser
extension PeerConnectionManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    // 發現 / 遺失 peer
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo _: [String: String]?) {
        DispatchQueue.main.async { self.discoveredPeers.append(peerID) }
    }
    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
    // 接收邀請
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext _: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 立即彈對話框；此處 Demo 直接接受
        invitationHandler(true, session)
    }
}
