import SwiftUI
import simd

struct PointerView: View {
    var direction: simd_float3
    var distance: Float?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            // 根據 UWB 提供的方向數據，計算角度
            let rawAngle = -atan2(Double(direction.x), Double(direction.z)) * 180 / .pi + 180
            let angle = (rawAngle > 180) ? rawAngle - 360 : rawAngle

            ZStack {
                Image(systemName: "arrowtriangle.up.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.red)
                    .rotationEffect(.degrees(angle)) // 旋轉圖標
                    .position(x: width / 2, y: height / 2 - 200)

                // 顯示距離和角度
                if let distance = distance {
                    Text("\(String(format: "%.2f", distance)) m \n \(String(format: "%.2f", angle)) °")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .position(x: width / 2, y: height / 2 - 150)
                }
            }
        }
    }
}
