//
//  DeviceRow.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import SwiftUI

/// 列表中的裝置行視圖
struct DeviceRow: View {
    let device: NearbyDevice

    var body: some View {
        HStack {
            Image(systemName: "iphone.gen2.radiowaves.left.and.right") // 使用一個合適的圖標
                .foregroundColor(device.distance != nil && device.direction != nil ? .blue : .orange)
            
            VStack(alignment: .leading) {
                Text(device.displayName)
                    .font(.headline)
                
                // 調試輸出 - 改進版本
                let _ = debuglog("\(device.displayName.prefix(5)) - distance: \(device.distance?.description ?? "nil"), direction: \(device.direction?.debugDescription ?? "nil"), lastUpdateTime: \(device.lastUpdateTime)")
                
                if let distance = device.distance {
                    Text(String(format: "距離: %.2f 公尺", distance))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("距離: 正在偵測...")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
                
                if let direction = device.direction {
                    // 簡單顯示方向向量，您可以轉換為更友好的描述 (例如：前方偏左)
                    // 這裡我們用Azimuth (水平方位角) 和 Elevation (俯仰角) 來描述
                    let azimuth = atan2(direction.x, direction.z) // 水平方位角 (弧度)
                    let elevation = asin(direction.y) // 俯仰角 (弧度)
                    Text(String(format: "方位角: %.0f°, 俯仰角: %.0f°", azimuth * 180 / .pi, elevation * 180 / .pi))
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                     Text("方向: 正在偵測...")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            // 可以加上一個指示燈表示 UWB 連接狀態
            Circle()
                .frame(width: 10, height: 10)
                .foregroundColor(device.distance != nil && device.direction != nil ? .green : .yellow)
        }
        .padding(.vertical, 4)
    }
}
