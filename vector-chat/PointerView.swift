import SwiftUI
import simd

struct PointerView: View {
    @ObservedObject var manager: NearbyInteractionManager // 引用 NearbyInteractionManager
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            if let smoothAngle = manager.smoothAngle {
                ZStack {
                    Image(systemName: "arrowtriangle.up.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.red)
                        .rotationEffect(.degrees(Double(smoothAngle))) // 使用平滑角度
                        .position(x: width / 2, y: height / 2 - 200)

                    if let distance = manager.distance {
                        Text("\(String(format: "%.2f", distance)) m \n \(String(format: "%.2f", smoothAngle)) °")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .position(x: width / 2, y: height / 2 - 150)
                    }
                }
            } else {
                Text("方向數據加載中...")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
        }
    }
}
