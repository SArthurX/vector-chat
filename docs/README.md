# Vector Chat Documentation

## 📚 Project Documentation

### Main Documentation
- [Project README (繁體中文)](../README.md) - Main project documentation in Traditional Chinese
- [Project README (English)](translations/README_EN.md) - English translation

### Development Documentation
- [Translation Guide](translations/README.md) - Multi-language documentation management

## 🏗️ Architecture Documentation

### Core Components
The project follows a modular architecture with clear separation of concerns:

#### Models
- `NearbyDevice.swift` - Device data representation
- `ChatModels.swift` - Chat-related data models
- `ChatInvitation.swift` - Chat invitation structures

#### Services
- `NearbyInteractionManager.swift` - Main UWB manager and ViewModel
- `MCService.swift` - MultipeerConnectivity service layer
- `NIService.swift` - NearbyInteraction service abstraction
- `ChatService.swift` - Chat functionality service
- `ChatManager.swift` - Chat session management

#### Views
- `ContentView.swift` - Main application view
- `RadarView.swift` - Interactive radar visualization
- `DeviceRow.swift` - Device list item component
- `DeviceMarkerView.swift` - Radar device marker

#### Utilities
- `DebugLogger.swift` - Centralized logging utility

## 🔧 Technical Specifications

### UWB Technology
- **Framework**: NearbyInteraction
- **Hardware**: U1 chip (iPhone 11+)
- **Precision**: Centimeter-level accuracy
- **Range**: Up to 10 meters effective distance

### Multi-device Architecture
- **Independent NISession per peer**: Each connected device has its own NISession instance
- **Token-based mapping**: Discovery tokens mapped to specific peers
- **Session lifecycle management**: Proper creation, configuration, and cleanup

### Connection Management
- **MultipeerConnectivity**: Peer-to-peer networking
- **Independent MCSession**: Each device pair uses separate sessions
- **Automatic discovery**: UUID-based invitation prioritization
- **Connection limits**: Support up to 8 simultaneous connections

## 🚀 Getting Started for Developers

### Prerequisites
1. Xcode 14.0 or later
2. iOS 15.0+ deployment target
3. Physical iPhone 11+ devices for UWB testing
4. Apple Developer account for device testing

### Development Setup
```bash
# Clone the repository
git clone https://github.com/SArthurX/vector-chat
cd vector-chat

# Open in Xcode
open vector-chat.xcodeproj

# Configure signing & capabilities
# Select your development team in Xcode project settings
```

### Key Development Notes
- UWB functionality requires physical devices (not available in simulator)
- Local network permissions required for MultipeerConnectivity
- Background mode limitations apply to UWB ranging
- Proper session lifecycle management critical for stability

## 📱 Testing Guidelines

### Multi-device Testing
1. Install on multiple UWB-capable devices
2. Ensure devices are on same local network
3. Grant necessary permissions on all devices
4. Test various distance ranges (1-10 meters)
5. Verify radar visualization accuracy

### Debug Logging
Enable comprehensive logging through `DebugLogger.swift`:
```swift
debuglog("Your debug message here")
```

## 🔄 Contribution Guidelines

### Code Style
- Follow Swift naming conventions
- Use meaningful variable and function names
- Add comprehensive documentation comments
- Maintain consistent indentation and formatting

### Architecture Principles
- Maintain separation of concerns
- Use reactive programming patterns (Combine)
- Implement proper error handling
- Follow SwiftUI best practices

### Pull Request Process
1. Fork the repository
2. Create feature branch from main
3. Implement changes with tests
4. Update documentation if needed
5. Submit pull request with clear description

---

For specific implementation details, please refer to the source code and inline documentation.
