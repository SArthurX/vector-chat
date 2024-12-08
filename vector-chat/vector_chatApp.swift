import SwiftUI

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
        //開始時先觸發onAppear
        .onAppear {
            nearbyInteractionManager.setupMultipeerConnectivity() //設置 MCSession,啟動廣播與搜尋
            nearbyInteractionManager.startSession() //啟動 NI Session,重啟 UWB 會話
        }
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
