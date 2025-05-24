//
//  RadarView.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import SwiftUI

/// 雷達視圖
struct RadarView: View {
    let devices: [NearbyDevice]
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // 雷達背景線 (可選)
                ForEach(0..<4) { i in
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        .frame(
                            width: CGFloat(i + 1) * 50 * scale,
                            height: CGFloat(i + 1) * 50 * scale
                        )
                        .position(x: center.x + offset.width, y: center.y + offset.height)
                }
                
                Line() // X 軸
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [5]))
                    .foregroundColor(.blue.opacity(0.5))
                    .frame(height: 1)
                    .position(x: center.x + offset.width, y: center.y + offset.height)
                
                Line(isVertical: true) // Y 軸
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [5]))
                    .foregroundColor(.blue.opacity(0.5))
                    .frame(width: 1)
                    .position(x: center.x + offset.width, y: center.y + offset.height)

                // 本機裝置 (中心點)
                Circle()
                    .fill(Color.green)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .position(x: center.x + offset.width, y: center.y + offset.height) // 中心點加上拖曳的偏移

                // 附近裝置
                ForEach(devices) { device in
                    if let position = device.position {
                        DeviceMarkerView(device: device)
                            .position(
                                x: center.x + (position.x * scale) + offset.width,
                                y: center.y + (position.y * scale) + offset.height // y 軸在地圖上是正常的，不需要反轉
                            )
                            .animation(.easeInOut(duration: 0.3), value: device.position) // 位置變化時動畫
                            .animation(.easeInOut(duration: 0.3), value: scale)
                            .animation(.easeInOut(duration: 0.3), value: offset)
                    }
                }
            }
            .clipped() // 超出邊界的視圖不顯示
        }
    }
}

/// 雷達圖中的水平線和垂直線
struct Line: Shape {
    var isVertical: Bool = false
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}
