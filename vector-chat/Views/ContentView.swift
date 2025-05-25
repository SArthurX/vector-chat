//
//  ContentView.swift
//  vector-chat
//
//  Created by Saxon on 2024/12/4.
//

import SwiftUI

/// 主視圖，包含雷達和裝置列表
struct ContentView: View {
    @StateObject private var interactionManager = NearbyInteractionManager()

    @State private var showUnsupportedDeviceAlert = false
    @State private var showNISessionInvalidatedAlert = false

    // 雷達視圖的縮放和拖曳狀態
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationView {
            VStack {
                if interactionManager.isUnsupportedDevice {
                    Text("此裝置不支援 UWB (Ultra Wideband)")
                        .foregroundColor(.red)
                        .padding()
                        .onAppear {
                            showUnsupportedDeviceAlert = true
                        }
                } else {
                    Text("本機裝置: \(interactionManager.localDeviceName)")
                        .font(.headline)
                        .padding(.top)

                    // 雷達視圖
                    RadarView(
                        devices: Array(interactionManager.nearbyDevices.values),
                        scale: $scale,
                        offset: $offset
                    )
                    .frame(height: 300) // 給雷達一個固定高度
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(15)
                    .padding()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale *= delta
                            }
                            .onEnded { value in
                                lastScale = 1.0
                            }
                    )
                    .simultaneousGesture( // 允許同時拖曳和縮放
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { value in
                                lastOffset = offset
                            }
                    )

                    Text("附近的裝置 (\(interactionManager.nearbyDevices.count))")
                        .font(.title2)
                        .padding(.top)

                    List {
                        ForEach(Array(interactionManager.nearbyDevices.values)) { device in
                            DeviceRow(device: device)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("UWB Nearby Radar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(interactionManager.isNISessionInvalidated ? "啟動" : "重新整理") {
                        if interactionManager.isNISessionInvalidated {
                            interactionManager.start()
                        } else {
                            // 簡單的重新整理：停止再開始（會重新廣播和掃描）
                            interactionManager.stop()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // 給一點時間停止
                                interactionManager.start()
                            }
                        }
                    }
                }
            }
            .onAppear {
                interactionManager.start() // App 出現時啟動
                // 可以在這裡設定一個 Timer 來定期清理超時的裝置
                Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
                    interactionManager.cleanupInactiveDevices()
                }
            }
            .onDisappear {
                // interactionManager.stop() // App 消失時停止 (視需求而定，若希望背景運作則不要停止)
            }
            .alert("不支援的裝置", isPresented: $showUnsupportedDeviceAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text("您的 iPhone 型號不支援 UWB (Ultra Wideband) 技術，此 App 的核心定位功能將無法使用。需要 iPhone 11 或更新的型號。")
            }
            .alert("Nearby Interaction Session 失效", isPresented: $showNISessionInvalidatedAlert) {
                Button("重新啟動", role: .destructive) {
                    interactionManager.start() // 嘗試重新啟動
                }
                Button("好", role: .cancel) { }
            } message: {
                Text("與附近裝置的互動 Session 已失效。這可能是因為 App 進入背景、權限問題或其他錯誤。您可以嘗試重新啟動。")
            }
            .onChange(of: interactionManager.isNISessionInvalidated) { newValue in
                if newValue {
                    // 避免在 isUnsupportedDevice 為 true 時也彈出這個警告
                    if !interactionManager.isUnsupportedDevice {
                        showNISessionInvalidatedAlert = true
                    }
                }
            }
        }
    }
}
