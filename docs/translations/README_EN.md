# Vector Chat - UWB Proximity Interaction App

An iOS application based on Apple's Ultra Wideband (UWB) technology and MultipeerConnectivity that precisely detects nearby iOS devices and displays their distance and direction.

## 🌐 Multi-language Support

This documentation is available in multiple languages:
- 🇺🇸 [English](README_EN.md) (Current version)
- 🇹🇼 [繁體中文](../../README.md) (Traditional Chinese)

View all available translations: [Translation Index](README.md)

## 🌟 Features

### Core Functionality
- **UWB Precise Ranging**: Centimeter-level precision using U1 chip in iPhone 11 or newer models
- **Direction Detection**: Display precise azimuth and elevation angles relative to the local device
- **Real-time Radar View**: Visualize surrounding device positions
- **Multi-device Support**: Support simultaneous connections with up to 8 devices

### Visual Interface
- **Interactive Radar**: Scalable and draggable circular radar view
- **Device List**: Display detailed information of all detected devices
- **Real-time Updates**: Distance and direction data updated in real-time
- **Status Indicators**: Visual UWB connection status display

### Advanced Features (In Development)
- **Chat Room Invitations**: Send chat invitations to nearby devices
- **Local Notifications**: Receive push notifications for chat invitations
- **Message Transmission**: Send text messages through established connections

## 📱 System Requirements

### Hardware Requirements
- **iPhone 11 or newer models** (equipped with U1 chip)
- **iOS 15.0 or later**

### Compatible Devices
- iPhone 11, 11 Pro, 11 Pro Max
- iPhone 12 series (12, 12 mini, 12 Pro, 12 Pro Max)
- iPhone 13 series and newer models
- iPhone 14 series and newer models
- iPhone 15 series and newer models

> **Note**: Devices that don't support UWB will display appropriate alerts but can still use basic device discovery features.

## 🏗️ Technical Architecture

### Core Technology Stack
```swift
- SwiftUI: Modern UI framework
- NearbyInteraction: Apple's UWB ranging framework
- MultipeerConnectivity: Inter-device network connections
- Combine: Reactive programming
- UserNotifications: Local notification support
```

### Architecture Design

```
Device A                          Device B
├─ startAdvertising               ├─ startBrowsing
├─ startBrowsing                  ├─ startAdvertising  
│                                 │
├─ Discover Device B              ├─ Discover Device A
├─ Send Connection Invitation ──→ ├─ Receive Invitation
│                                 ├─ Establish MCSession
├─ Exchange Discovery Token ←───→ ├─ Exchange Discovery Token
├─ Create NISession               ├─ Create NISession
├─ Start UWB Ranging ←──────────→ ├─ Start UWB Ranging
└─ Real-time Distance/Direction   └─ Real-time Distance/Direction
```

## 📁 Project Structure

```
vector-chat/
├── Models/
│   ├── NearbyDevice.swift          # Device data model
│   ├── ChatModels.swift            # Chat-related data models (In development)
│   └── ChatInvitation.swift        # Chat invitation model
├── Services/
│   ├── MCService.swift             # MultipeerConnectivity service
│   ├── NearbyInteractionManager.swift  # UWB manager (Main ViewModel)
│   ├── NIService.swift             # NearbyInteraction service
│   ├── ChatService.swift           # Chat service (In development)
│   ├── ChatManager.swift           # Chat manager (In development)
│   └── ChatroomManager.swift       # Chatroom manager (In development)
├── Views/
│   ├── ContentView.swift           # Main view
│   ├── RadarView.swift             # Radar view component
│   ├── DeviceRow.swift             # Device list item
│   └── DeviceMarkerView.swift      # Device marker for radar
├── Utilities/
│   └── DebugLogger.swift           # Debug logging utility
└── Extensions/
    └── NINearbyObject+Extensions.swift  # NearbyInteraction extensions
```

## 🚀 Quick Start

### Installation Steps

1. **Clone the Project**
   ```bash
   git clone https://github.com/SArthurX/vector-chat
   cd vector-chat
   ```

2. **Open Xcode Project**
   ```bash
   open vector-chat.xcodeproj
   ```

3. **Configure Developer Certificate**
   - Select your development team in Xcode
   - Ensure proper Bundle Identifier is set

4. **Build and Run**
   - Select a physical iPhone device that supports UWB
   - Press Cmd+R to build and run

### Permission Setup

The application requires the following permissions:
- **Local Network Access**: For MultipeerConnectivity
- **Nearby Interaction**: For UWB ranging functionality
- **Notification Permission**: For chat invitation notifications (optional)

### Usage Instructions

1. **Launch Application**: Open the app on a UWB-supported iPhone
2. **Multi-device Testing**: Also launch the app on another UWB-supported iPhone
3. **Automatic Discovery**: Devices will automatically discover and connect
4. **View Ranging**: Check real-time distance and direction in radar view and device list

## 🔧 Development Guide

### Main Component Overview

#### NearbyInteractionManager
```swift
/// UWB and multi-peer connection manager (Main ViewModel)
class NearbyInteractionManager: NSObject, ObservableObject {
    @Published var nearbyDevices: [MCPeerID: NearbyDevice] = [:]
    @Published var isNISessionInvalidated = false
    @Published var isUnsupportedDevice = false
    
    // Core methods
    func start()    // Start service
    func stop()     // Stop service
}
```

#### MCService
```swift
/// MultipeerConnectivity service management
class MCService: NSObject, ObservableObject {
    @Published var connectedPeers: Set<MCPeerID> = []
    @Published var discoveredPeers: Set<MCPeerID> = []
    
    // Support up to 8 simultaneous device connections
    // Each device pair uses independent MCSession
}
```

#### NearbyDevice
```swift
/// Nearby device data model
struct NearbyDevice: Identifiable, Equatable {
    let id: MCPeerID
    var displayName: String
    var distance: Float?          // Distance (meters)
    var direction: simd_float3?   // 3D direction vector
    var lastUpdateTime: Date
}
```

### Debugging and Testing

#### Enable Debug Logging
```swift
// Configure in DebugLogger.swift
#if DEBUG
    print("\(timestamp) >>> \(message)")
#endif
```

#### Common Troubleshooting

1. **UWB Not Supported Error**
   - Ensure using iPhone 11 or newer model
   - Check iOS version is 15.0 or later

2. **Devices Cannot Be Discovered**
   - Ensure both devices are on the same Wi-Fi network
   - Check local network permission settings
   - Restart the application

3. **Inaccurate Ranging**
   - Ensure no metal objects blocking between devices
   - Keep devices within 10 meters
   - Avoid electromagnetic interference environments

### Extension Development

#### Adding New Features
1. Create new files in appropriate directories
2. Follow existing architectural patterns
3. Use `@Published` properties to support SwiftUI binding
4. Add appropriate error handling and logging

#### Chat Feature Development (In Progress)
```swift
// Planned features
- Chat invitation sending/receiving
- Real-time message transmission
- Chatroom management
- Local notification integration
```

## 📚 Related Resources

### Apple Official Documentation
- [NearbyInteraction Framework](https://developer.apple.com/documentation/nearbyinteraction)
- [MultipeerConnectivity Framework](https://developer.apple.com/documentation/multipeerconnectivity)
- [Ultra Wideband Technology](https://developer.apple.com/ultra-wideband/)

### Technical References
- [WWDC 2020: Meet Nearby Interaction](https://developer.apple.com/videos/play/wwdc2020/10668/)
- [Human Interface Guidelines - Nearby Interaction](https://developer.apple.com/design/human-interface-guidelines/nearby-interaction)

## 🐛 Known Issues

1. **Background Mode Limitations**: UWB functionality pauses when app enters background
2. **Battery Consumption**: Continuous UWB usage increases battery consumption
3. **Distance Limitations**: Effective ranging distance approximately 10 meters
4. **Environmental Impact**: Metal surfaces may affect ranging accuracy

## 🔄 Version History

### v1.0.0 (Current Version)
- ✅ Basic UWB ranging functionality
- ✅ Multi-device connection support
- ✅ Interactive radar view
- ✅ Real-time distance and direction display
- 🔄 Chatroom functionality (In development)

## 🤝 Contributing

1. Fork the project
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## 👨‍💻 Author

Saxon - December 4, 2024

---

**Note**: This application requires physical iPhone devices for testing; simulators do not support UWB functionality.
