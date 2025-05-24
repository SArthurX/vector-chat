//
//  DeviceMarkerView.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import SwiftUI

/// 裝置在雷達上的標記視圖
struct DeviceMarkerView: View {
    let device: NearbyDevice
    @State private var showingActionSheet = false // 控制是否顯示操作選單

    var body: some View {
        VStack {
            Circle()
                .fill(device.distance != nil ? Color.blue : Color.orange) // 有距離方向用藍色，否則橘色 (表示已 MCP 連接但 UWB 未就緒)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                .onTapGesture {
                    print("點擊了裝置: \(device.displayName)")
                    showingActionSheet = true // 點擊時顯示選單
                }
            Text(device.displayName.prefix(3)) // 顯示名稱前綴
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .actionSheet(isPresented: $showingActionSheet) {
            ActionSheet(
                title: Text("操作選項: \(device.displayName)"),
                message: Text(device.distance != nil ? String(format: "距離: %.2f 公尺", device.distance!) : "距離未知"),
                buttons: [
                    .default(Text("發送聊天邀請 (待實作)")) {
                        // TODO: 實作發送聊天邀請的邏輯
                        print("TODO: 向 \(device.displayName) 發送聊天邀請")
                    },
                    .cancel(Text("取消"))
                ]
            )
        }
    }
}
