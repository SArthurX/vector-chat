import SwiftUI
import simd
import NearbyInteraction


struct RadarView: View {
    var devices: [NINearbyObject] // 包含多個設備的方向和距離

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let centerX = width / 2
            let centerY = height / 2
            let maxRadius = min(centerX, centerY) * 0.8 // 限制最大範圍

            ZStack {
                // 雷達背景
                ForEach(0..<4) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        .frame(width: CGFloat(i + 1) * maxRadius / 2, height: CGFloat(i + 1) * maxRadius / 2)
                        .position(x: centerX, y: centerY)
                }
                
                // 旋轉的掃描條
                RadarScannerView()
                    .frame(width: maxRadius * 2, height: maxRadius * 2)
                    .position(x: centerX, y: centerY)
                
                // 顯示裝置位置的點
                ForEach(devices.indices, id: \.self) { index in
                    let device = devices[index]
                    if let distance = device.distance, let direction = device.direction {
                        let normalizedDistance = min(Float(distance), 4.0) / 4.0 // 以4米為範圍限制
                        let radius = CGFloat(normalizedDistance) * maxRadius
                        let angle = atan2(Double(direction.x), Double(direction.z)) // 根據方向計算角度
                        
                        let xOffset = radius * CGFloat(cos(angle))
                        let yOffset = radius * CGFloat(sin(angle))

                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .position(x: centerX + xOffset, y: centerY - yOffset) // 使用負 yOffset，因為 y 軸是向下的
                        
                        // 顯示裝置的距離
                        Text("\(String(format: "%.2f", distance)) m")
                            .font(.caption)
                            .foregroundColor(.white)
                            .position(x: centerX + xOffset, y: centerY - yOffset - 15)
                    }
                }
            }
        }
    }
}

struct RadarScannerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(Color.green.opacity(0.6), lineWidth: 2)
            .frame(width: 200, height: 200)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
