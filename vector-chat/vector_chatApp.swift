import SwiftUI
import simd

@main
struct NearbyInteractionApp: App {
    @StateObject private var nearbyInteractionManager = NearbyInteractionManager()

    var body: some Scene {
        WindowGroup {
            ContentView(nearbyInteractionManager: nearbyInteractionManager)
                .overlay(
                    Group {
                        if nearbyInteractionManager.isChatOpen {
                            VStack {
                                Text("聊天視窗")
                                // 在此放置可擴充的聊天 UI
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.5))
                        }
                    }
                )
        }
    }
}

// ContentView
struct ContentView: View {
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager

    var body: some View {
        VStack(spacing: 20) { // 主 VStack，元素間距 20
            VStack(spacing: 10) { // 標題和距離顯示
                Text("Nearby Interaction.")
                    .font(.largeTitle)

                if let distance = nearbyInteractionManager.distance {
                    Text("距離: \(String(format: "%.2f", distance)) 公尺")
                        .font(.headline)
                } else {
                    Text("正在測量距離...")
                        .font(.headline)
                }
            }
            .padding()

            RadarView(devices: nearbyInteractionManager.nearbyDevices)
                .frame(height: 300) // 雷達視圖高度
                .padding()

            if let _ = nearbyInteractionManager.smoothAngle {
                PointerView(manager: nearbyInteractionManager)
                    .padding()
            } else {
                Text("方向數據加載中...")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding()
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

            if let angle = nearbyInteractionManager.smoothAngle, !nearbyInteractionManager.isChatOpen {
                Button("發送聊天請求") {
                    nearbyInteractionManager.sendChatRequest()
                }
                .padding()
                .background(angle >= -10 && angle <= 10 ? Color.green : Color.red)
                .foregroundColor(angle >= -10 && angle <= 10 ? Color.white : Color.white)
                .cornerRadius(10)
                .disabled(!(angle >= -10 && angle <= 10))
            }

            Spacer() // 確保內容靠上排列
        }
        .onAppear {
            nearbyInteractionManager.setupMultipeerConnectivity()
            nearbyInteractionManager.startSession()
        }
    }
}

//#Preview {
//    ContentView()
//}
