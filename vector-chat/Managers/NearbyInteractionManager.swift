import Foundation
import NearbyInteraction
import MultipeerConnectivity
import Combine
import simd

final class NearbyInteractionManager: NSObject, ObservableObject {
    @Published var objects: [MCPeerID: NINearbyObject] = [:]
    
    // 對外 Combine
    let didUpdate = PassthroughSubject<(MCPeerID, Float, simd_float3), Never>()
    
    private var sessions: [MCPeerID: NISession] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
    }
    
    // 建立 / 重用 NISession
    func configureSession(with peerID: MCPeerID, token: NIDiscoveryToken) {
        let session: NISession
        if let existing = sessions[peerID] {
            session = existing
        } else {
            session = NISession()
            session.delegate = self
            sessions[peerID] = session
        }
        let config = NINearbyPeerConfiguration(peerToken: token)
        session.run(config)
    }
}

// MARK: – NISessionDelegate
extension NearbyInteractionManager: NISessionDelegate {
    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let peer = sessions.first(where: { $0.value == session })?.key else { return }
        sessions.removeValue(forKey: peer)
        DispatchQueue.main.async { self.objects.removeValue(forKey: peer) }
    }
    
    func session(_ session: NISession,
                 didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first,
              let peerID = sessions.first(where: { $0.value == session })?.key,
              let distance = object.distance,
              let direction = object.direction else { return }

        print("[NI] \(peerID.displayName) distance = \(distance) m, dir = \(direction)") //debug
        
        DispatchQueue.main.async {
            self.objects[peerID] = object
            self.didUpdate.send((peerID, distance, direction))
        }
    }
}
