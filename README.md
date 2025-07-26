# AR Tweet App 🐦✨

An innovative iOS ARKit application that allows users to create and manage 3D tweets in augmented reality space.

![AR Tweet App](https://img.shields.io/badge/iOS-11.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)
![ARKit](https://img.shields.io/badge/ARKit-2.0-red.svg)

## 🌟 Features

### **3D Tweet Creation**
- Create floating 3D text in AR space
- Large, visible white text with glow effects
- Positioned at natural eye level for optimal viewing
- Smooth scale-in animations

### **Tweet History Management**
- 📝 History button in top-left corner
- Dropdown list of all created tweets
- Individual delete buttons (🗑️) for each tweet
- Clean, organized interface

### **User Experience**
- Simple text input field
- One-tap tweet creation
- Intuitive history management
- Smooth animations throughout

## 📱 Screenshots

*Coming soon - Add screenshots of your app in action!*

## 🚀 Getting Started

### Prerequisites
- iOS 11.0 or later
- iPhone 6s/SE or newer (A9 processor required for ARKit)
- Xcode 10.0 or later
- Apple Developer Account (for device testing)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/ar-tweet-app.git
   cd ar-tweet-app
   ```

2. **Open in Xcode**
   ```bash
   open ARKitDraw.xcodeproj
   ```

3. **Configure signing**
   - Select the project in Xcode
   - Go to "Signing & Capabilities"
   - Check "Automatically manage signing"
   - Select your Apple ID/Team

4. **Build and run**
   - Connect your iOS device
   - Press ⌘+R or click the Play button
   - Grant camera permissions when prompted

## 🎮 How to Use

### Creating Tweets
1. **Launch the app** on your iOS device
2. **Point camera** around to let ARKit calibrate
3. **Type your tweet** in the text field at the bottom
4. **Tap "Enter"** or press return
5. **Watch** your tweet appear as 3D text in AR space!

### Managing Tweet History
1. **Tap the 📝 button** in the top-left corner
2. **View all tweets** in the dropdown list
3. **Tap 🗑️** next to any tweet to delete it
4. **Tap 📝 again** to hide the history

### Tips for Best Experience
- **Good lighting** helps ARKit track the environment better
- **Move slowly** when placing tweets for better positioning
- **Walk around** to see tweets from different angles
- **Keep device steady** when creating tweets

## 🛠️ Technical Details

### Built With
- **ARKit 2.0** - Augmented Reality framework
- **SceneKit** - 3D graphics rendering
- **UIKit** - User interface components
- **Swift 5.0** - Programming language

### Architecture
- **ViewController** - Main AR view controller
- **ARSCNView** - AR scene view for rendering
- **SCNText** - 3D text geometry
- **UITableView** - Tweet history management

### Key Components
- `ViewController.swift` - Main app logic
- `Main.storyboard` - UI layout
- `SCNVector3Extensions.swift` - Vector math utilities

## 🎯 Features in Detail

### AR Text Rendering
- **Font Size**: 0.3 units (large and visible)
- **Color**: White with emission glow
- **Positioning**: 0.5 units in front of camera
- **Constraints**: Billboard constraint (always faces camera)
- **Animation**: Scale-in from 0 to 1.0 over 0.3 seconds

### History Management
- **Button**: Circular 📝 button with dark background
- **Dropdown**: 250x200px table view with dark theme
- **Deletion**: Individual trash buttons with fade-out animation
- **State Management**: Arrays track both nodes and text content

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **ARKit** by Apple for the amazing AR framework
- **SceneKit** for 3D rendering capabilities
- **Original line drawing project** that inspired this AR tweet concept

## 📞 Support

If you have any questions or need help:
- Open an issue on GitHub
- Check the troubleshooting section below

## 🔧 Troubleshooting

### Common Issues

**"ARKit requires a device with A9 processor"**
- Use iPhone 6s/SE or newer, or iPad Pro

**"Camera permissions denied"**
- Go to Settings > Privacy > Camera > AR Tweet App > Allow

**"Text not visible"**
- Ensure good lighting
- Move closer to where you placed the tweet
- Check that text size is appropriate

**"App crashes on launch"**
- Ensure iOS 11.0+ is installed
- Check that ARKit is supported on your device

---

**Made with ❤️ using ARKit and Swift**
