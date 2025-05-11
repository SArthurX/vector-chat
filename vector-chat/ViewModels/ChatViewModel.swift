import Foundation
import Combine
import MultipeerConnectivity

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    struct ChatMessage: Identifiable {
        let id = UUID()
        let sender: String
        let text: String
    }
    
    private let peerManager: PeerConnectionManager
    private var cancellables = Set<AnyCancellable>()
    
    init(peerManager: PeerConnectionManager) {
        self.peerManager = peerManager
        
        peerManager.receivedChat
            .sink { [weak self] peer, text in
                self?.messages.append(
                    ChatMessage(sender: peer.displayName, text: text))
            }
            .store(in: &cancellables)
    }
    
    func send(_ text: String) {
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(sender: "Me", text: text))
        peerManager.sendChat(text, to: peerManager.session.connectedPeers)
    }
}
