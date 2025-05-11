import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var chatVM: ChatViewModel
    @State private var draft = ""
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack {
                        ForEach(chatVM.messages) { msg in
                            HStack(alignment: .top) {
                                Text(msg.sender)
                                    .font(.caption2).foregroundColor(.gray)
                                Text(msg.text)
                                    .padding(8)
                                    .background(.green.opacity(0.2))
                                    .cornerRadius(8)
                                Spacer()
                            }
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chatVM.messages.count) { _ in
                    // 捲到最底
                    if let last = chatVM.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            
            HStack {
                TextField("訊息…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("傳送") {
                    chatVM.send(draft)
                    draft = ""
                }
            }
            .padding()
        }
        .navigationTitle("聊天室")
    }
}
