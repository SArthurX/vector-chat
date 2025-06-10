# Vector Chat - UWB 近距離互動應用

一個基於 Apple 的 Ultra Wideband (UWB) 技術和 MultipeerConnectivity 的 iOS 應用程式，可以精確偵測附近的 iOS 裝置並顯示其距離和方向。

## 🌐 多語言支援

本文檔提供多種語言版本：
- 🇺🇸 [English](../../README.md) (主要版本)
- 🇹🇼 [繁體中文](README_ZH-TW.md) (當前版本)

查看所有可用翻譯：[翻譯索引](README.md)

## 🌟 功能特色

### 核心功能
- **UWB 精確測距**：使用 iPhone 11 或更新型號的 U1 晶片進行公分級精確測距
- **方向偵測**：顯示其他裝置相對於本機的精確方位角和俯仰角
- **即時雷達視圖**：以視覺化方式顯示周圍裝置的位置
- **多裝置支援**：同時支援最多 8 個裝置的連接

### 視覺化介面
- **互動式雷達**：可縮放和拖曳的圓形雷達視圖
- **裝置列表**：顯示所有偵測到裝置的詳細資訊
- **即時更新**：距離和方向資料即時更新
- **狀態指示器**：視覺化顯示 UWB 連接狀態

### 進階功能 (開發中)
- **聊天室邀請**：向附近裝置發送聊天邀請
- **本地通知**：接收聊天邀請的推播通知
- **訊息傳送**：透過已建立的連接發送文字訊息

## 📱 系統需求

### 硬體需求
- **iPhone 11 或更新型號** (配備 U1 晶片)
- **iOS 15.0 或更新版本**

### 相容裝置
- iPhone 11, 11 Pro, 11 Pro Max
- iPhone 12 系列 (12, 12 mini, 12 Pro, 12 Pro Max)
- iPhone 13 系列及更新型號
- iPhone 14 系列及更新型號
- iPhone 15 系列及更新型號

> **注意**：不支援 UWB 的裝置將顯示相應提示，但仍可使用基本的裝置發現功能。

## 🏗️ 技術架構

### 核心技術棧
```swift
- SwiftUI：現代化的 UI 框架
- NearbyInteraction：Apple 的 UWB 測距框架
- MultipeerConnectivity：裝置間的網路連接
- Combine：響應式程式設計
- UserNotifications：本地通知支援
```

### 架構設計

```
設備 A                           設備 B
├─ startAdvertising                ├─ startBrowsing
├─ startBrowsing                   ├─ startAdvertising  
│                                  |
├─ 發現設備                         ├─ 發現設備 A
├─ 發送連接邀請  ─────────────────→  ├─ 接收邀請
│                                  ├─ 建立 MCSession
├─ 交換 Discovery Token ←────────→  ├─ 交換 Discovery Token
├─ 建立 NISession                   ├─ 建立 NISession
├─ 開始 UWB 測距 ←───────────────→   ├─ 開始 UWB 測距
└─ 即時距離/方向更新              └─ 即時距離/方向更新
```

## 📁 專案結構

```
vector-chat/
├── Models/
│   ├── NearbyDevice.swift          # 裝置資料模型
│   └── ChatModels.swift            # 聊天相關資料模型 (開發中)
├── Services/
│   ├── MCService.swift             # MultipeerConnectivity 服務
│   ├── NearbyInteractionManager.swift  # UWB 管理器 (主要 ViewModel)
│   ├── NIService.swift             # NearbyInteraction 服務
│   └── ChatroomManager.swift       # 聊天室管理器 (開發中)
├── Views/
│   ├── ContentView.swift           # 主視圖
│   ├── RadarView.swift             # 雷達視圖組件
│   └── DeviceRow.swift             # 裝置列表項目
├── Utilities/
│   └── DebugLogger.swift           # 調試日誌工具
└── Extensions/
    └── NINearbyObject+Extensions.swift  # NearbyInteraction 擴展
```

## 🚀 快速開始

### 安裝步驟

1. **克隆專案**
   ```bash
   git clone https://github.com/SArthurX/vector-chat
   cd vector-chat
   ```

2. **打開 Xcode 專案**
   ```bash
   open vector-chat.xcodeproj
   ```

3. **設定開發者憑證**
   - 在 Xcode 中選擇你的開發團隊
   - 確保已設定適當的 Bundle Identifier

4. **編譯並運行**
   - 選擇支援 UWB 的實體 iPhone 設備
   - 按 Cmd+R 編譯並運行

### 權限設定

應用程式需要以下權限：
- **本地網路存取**：用於 MultipeerConnectivity
- **附近互動**：用於 UWB 測距功能
- **通知權限**：用於聊天邀請通知 (可選)

### 使用說明

1. **啟動應用程式**：在支援 UWB 的 iPhone 上打開應用
2. **多裝置測試**：在另一台支援 UWB 的 iPhone 上也啟動應用
3. **自動發現**：裝置將自動發現並連接
4. **查看測距**：在雷達視圖和裝置列表中查看即時距離和方向

## 🔧 開發指南

### 主要組件說明

#### NearbyInteractionManager
```swift
/// UWB 和多點連接管理器 (主要 ViewModel)
class NearbyInteractionManager: NSObject, ObservableObject {
    @Published var nearbyDevices: [MCPeerID: NearbyDevice] = [:]
    @Published var isNISessionInvalidated = false
    @Published var isUnsupportedDevice = false
    
    // 核心方法
    func start()    // 啟動服務
    func stop()     // 停止服務
}
```

#### MCService
```swift
/// MultipeerConnectivity 服務管理
class MCService: NSObject, ObservableObject {
    @Published var connectedPeers: Set<MCPeerID> = []
    @Published var discoveredPeers: Set<MCPeerID> = []
    
    // 支援最多 8 個裝置同時連接
    // 每對裝置使用獨立的 MCSession
}
```

#### NearbyDevice
```swift
/// 附近裝置的資料模型
struct NearbyDevice: Identifiable, Equatable {
    let id: MCPeerID
    var displayName: String
    var distance: Float?          // 距離（公尺）
    var direction: simd_float3?   // 3D 方向向量
    var lastUpdateTime: Date
}
```

### 調試和測試

#### 啟用調試日誌
```swift
// 在 DebugLogger.swift 中設定
#if DEBUG
    print("\(timestamp) >>> \(message)")
#endif
```

#### 常見問題排解

1. **UWB 不支援錯誤**
   - 確保使用 iPhone 11 或更新型號
   - 檢查 iOS 版本是否為 15.0 或更新

2. **裝置無法發現**
   - 確保兩台裝置都在同一個 Wi-Fi 網路
   - 檢查本地網路權限設定
   - 重啟應用程式

3. **測距不準確**
   - 確保裝置間沒有金屬物體阻擋
   - 保持裝置在 10 公尺以內
   - 避免電磁干擾環境

### 擴展開發

#### 添加新功能
1. 在適當的目錄創建新檔案
2. 遵循現有的架構模式
3. 使用 `@Published` 屬性支援 SwiftUI 綁定
4. 添加適當的錯誤處理和日誌

#### 聊天功能開發 (進行中)
```swift
// 預計功能
- 聊天邀請發送/接收
- 即時訊息傳送
- 聊天室管理
- 本地通知整合
```

## 📚 相關資源

### Apple 官方文檔
- [NearbyInteraction Framework](https://developer.apple.com/documentation/nearbyinteraction)
- [MultipeerConnectivity Framework](https://developer.apple.com/documentation/multipeerconnectivity)
- [Ultra Wideband Technology](https://developer.apple.com/ultra-wideband/)

### 技術參考
- [WWDC 2020: Meet Nearby Interaction](https://developer.apple.com/videos/play/wwdc2020/10668/)
- [Human Interface Guidelines - Nearby Interaction](https://developer.apple.com/design/human-interface-guidelines/nearby-interaction)

## 🐛 已知問題

1. **背景模式限制**：應用進入背景時 UWB 功能會暫停
2. **電池消耗**：連續使用 UWB 會增加電池消耗
3. **距離限制**：有效測距範圍約為 10 公尺
4. **環境影響**：金屬表面可能影響測距精度

## 🔄 版本歷史

### v1.0.0 (當前版本)
- ✅ 基本 UWB 測距功能
- ✅ 多裝置連接支援
- ✅ 互動式雷達視圖
- ✅ 即時距離和方向顯示
- 🔄 聊天室功能 (開發中)

## 🤝 貢獻指南

1. Fork 專案
2. 創建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交變更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 創建 Pull Request

## 📄 授權條款

本專案採用 MIT 授權條款 - 詳見 [LICENSE](LICENSE) 檔案

## 👨‍💻 作者

Saxon - 2024/12/4

---

**注意**：此應用程式需要實體 iPhone 裝置進行測試，模擬器不支援 UWB 功能。
