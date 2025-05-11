import Foundation

enum Dependency {
    static let peer = PeerConnectionManager()
    static let nearby = NearbyInteractionManager()
}