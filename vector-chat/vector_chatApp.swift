import SwiftUI

@main
struct vector_chatApp: App {
    @StateObject private var peerManager = PeerConnectionManager()
    @StateObject private var nearbyManager = NearbyInteractionManager()
    
    var body: some Scene {
        WindowGroup {
            RadarView()
                .environmentObject(peerManager)
                .environmentObject(nearbyManager)
        }
    }
}
