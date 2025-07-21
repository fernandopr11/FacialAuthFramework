# FacialAuth Framework

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-FA7343.svg?style=for-the-badge&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/iOS-14.0+-000000.svg?style=for-the-badge&logo=ios" alt="iOS">
  <img src="https://img.shields.io/badge/SPM-compatible-orange.svg?style=for-the-badge" alt="SPM">
  <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License">
</p>

<p align="center">
  <strong>Advanced facial authentication framework for iOS with TrueDepth Camera, Core ML and Vision Framework</strong>
</p>

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [User Registration](#user-registration)
- [Authentication](#authentication)
- [Delegate Implementation](#delegate-implementation)
- [User Management](#user-management)
- [Error Handling](#error-handling)
- [Advanced Configuration](#advanced-configuration)
- [Security](#security)
- [Debug & Metrics](#debug--metrics)
- [Usage Examples](#usage-examples)
- [License](#license)

---

## Features

### Advanced Technology
- ✅ **Facial Embeddings**: >95% accuracy with 512-dimensional vectors
- ✅ **TrueDepth Camera**: Full support with 3D depth data
- ✅ **Core ML + Vision**: Native iOS-optimized processing
- ✅ **Real-time**: Detection and intelligent auto-capture

### Enterprise Security
- ✅ **AES-256-GCM Encryption**: Completely protected biometric data
- ✅ **Keychain Storage**: Secure storage in device hardware
- ✅ **Local Processing**: No internet connection, 100% private
- ✅ **Embeddings Only**: Never stores images, only mathematical vectors

### Developer Experience
- ✅ **Simple API**: Integration in less than 10 lines
- ✅ **Multi-user**: Unlimited registered users
- ✅ **Complete Callbacks**: Full flow control
- ✅ **Debug Mode**: Detailed logging for development

## Requirements

| Requirement | Version |
|-------------|---------|
| **iOS** | 14.0+ |
| **Xcode** | 15.0+ |
| **Swift** | 5.9+ |
| **Camera** | Front-facing (TrueDepth recommended) |

**Compatible Devices**: iPhone X+, iPad Pro 2018+, others with front camera

## Installation

### Swift Package Manager (Recommended)

```
https://github.com/fernandopr11/FacialAuthFramework.git
```

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/fernandopr11/FacialAuthFramework.git", from: "1.0.0")
]
```

### CocoaPods

```ruby
pod 'FacialAuthFramework', '~> 1.0'
```

## Quick Start

### 1. Configure Permissions

Add to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for secure facial authentication</string>
```

### 2. Basic Setup

```swift
import FacialAuthFramework

class ViewController: UIViewController {
    private var facialAuthManager: FacialAuthManager!
    @IBOutlet weak var cameraPreviewView: UIView!
    @IBOutlet weak var statusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFacialAuth()
    }
    
    private func setupFacialAuth() {
        let config = AuthConfiguration(
            similarityThreshold: 0.85,
            debugMode: true
        )
        
        facialAuthManager = FacialAuthManager(configuration: config)
        facialAuthManager.delegate = self
        facialAuthManager.initialize()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        facialAuthManager.setupCameraPreview(in: self, previewView: cameraPreviewView)
    }
}
```

### 3. Implement Basic Delegate

```swift
extension ViewController: FacialAuthDelegate {
    func authenticationDidSucceed(userProfile: UserProfile) {
        statusLabel.text = "✅ Welcome, \(userProfile.displayName)"
    }
    
    func authenticationDidFail(error: AuthError) {
        statusLabel.text = "❌ Error: \(error.localizedDescription)"
    }
    
    func registrationDidSucceed(userProfile: UserProfile) {
        statusLabel.text = "✅ User registered: \(userProfile.displayName)"
    }
    
    func registrationDidFail(error: AuthError) {
        statusLabel.text = "❌ Registration error: \(error.localizedDescription)"
    }
    
    func registrationProgress(_ progress: Float) {
        statusLabel.text = "Registering: \(Int(progress * 100))%"
    }
}
```

### 4. Use the Framework

```swift
// Register new user
@IBAction func registerUser() {
    facialAuthManager.registerUser(
        userId: "user123",
        displayName: "John Doe",
        in: self
    )
}

// Authenticate existing user
@IBAction func authenticateUser() {
    facialAuthManager.authenticateUser(userId: "user123", in: self)
}

// Check if user exists
if facialAuthManager.isUserRegistered(userId: "user123") {
    print("User already registered")
}
```

## Configuration

### AuthConfiguration

```swift
let config = AuthConfiguration(
    // Authentication precision
    similarityThreshold: 0.85,          // 0.0-1.0 (0.85 recommended)
    maxAttempts: 3,                     // Attempts before blocking
    sessionTimeout: 300,                // 5 minutes
    
    // Camera configuration
    enableTrueDepth: true,              // Use depth data
    cameraQuality: .high,               // .medium, .high, .ultra
    
    // Development
    debugMode: false,                   // Detailed logs
    logMetrics: false,                  // Performance metrics
    
    // Training
    trainingMode: .standard,            // .fast, .standard, .deep
    maxTrainingSamples: 50              // Samples per user
)
```

### Training Modes

| Mode | Epochs | Time | Precision | Recommended Use |
|------|--------|------|-----------|-----------------|
| `.fast` | 3 | ~30s | High | Development, testing |
| `.standard` | 8 | ~60s | Very High | General production |
| `.deep` | 15 | ~120s | Maximum | Critical apps |

## User Registration

### Automatic Process

Registration includes 3 phases that execute automatically:

1. **Sample Capture** (0-50%): Automatically captures 50 images
2. **Embedding Extraction** (50-80%): Core ML processing
3. **Training** (80-100%): Creates personalized model

```swift
func registerNewUser() {
    let userId = UUID().uuidString
    let displayName = "Maria Garcia"
    
    facialAuthManager.registerUser(
        userId: userId,
        displayName: displayName,
        in: self
    )
}
```

### Registration Callbacks

```swift
// Overall progress (0.0 - 1.0)
func registrationProgress(_ progress: Float) {
    progressView.progress = progress
    progressLabel.text = "Progress: \(Int(progress * 100))%"
}

// Each captured sample
func trainingSampleCaptured(sampleCount: Int, totalNeeded: Int) {
    statusLabel.text = "Sample \(sampleCount)/\(totalNeeded) captured"
}

// Quality validation
func trainingDataValidated(isValid: Bool, quality: Float) {
    if isValid {
        statusLabel.text = "✅ High quality sample"
    } else {
        statusLabel.text = "⚠️ Improve lighting"
    }
}
```

## Authentication

### Simple Process

Authentication is a straightforward 1-photo process:

1. **Capture**: Takes a photo of current user
2. **Comparison**: Compares with stored embeddings
3. **Result**: Success/failure based on similarity threshold

```swift
func authenticateExistingUser() {
    let userId = "user123"
    
    // Verify user exists
    guard facialAuthManager.isUserRegistered(userId: userId) else {
        showAlert("User not registered")
        return
    }
    
    facialAuthManager.authenticateUser(userId: userId, in: self)
}
```

### Result Handling

```swift
func authenticationDidSucceed(userProfile: UserProfile) {
    print("User: \(userProfile.displayName)")
    print("Registration date: \(userProfile.createdAt)")
    print("Samples: \(userProfile.samplesCount)")
    
    // Navigate to main screen
    navigateToMainScreen()
}

func authenticationDidFail(error: AuthError) {
    switch error {
    case .faceNotDetected:
        showAlert("Position your face in front of the camera")
    case .similarityThresholdNotMet:
        showAlert("Face doesn't match the registered profile")
    case .maxAttemptsExceeded:
        showAlert("Too many failed attempts")
    default:
        showAlert(error.localizedDescription)
    }
}
```

## Delegate Implementation

### Complete Protocol

```swift
public protocol FacialAuthDelegate: AnyObject {
    // Authentication
    func authenticationDidSucceed(userProfile: UserProfile)
    func authenticationDidFail(error: AuthError)
    func authenticationDidCancel()
    
    // Registration
    func registrationDidSucceed(userProfile: UserProfile)
    func registrationDidFail(error: AuthError)
    func registrationProgress(_ progress: Float)
    
    // System state
    func authenticationStateChanged(_ state: AuthState)
    func cameraPermissionRequired()
    
    // Training (optional)
    func trainingDidStart(mode: TrainingMode)
    func trainingProgress(_ progress: Float, epoch: Int, loss: Float, accuracy: Float)
    func trainingDidComplete(metrics: TrainingMetrics)
    func trainingSampleCaptured(sampleCount: Int, totalNeeded: Int)
    func trainingDataValidated(isValid: Bool, quality: Float)
    
    // Metrics (optional)
    func metricsUpdated(_ metrics: AuthMetrics)
}
```

### System States

```swift
public enum AuthState {
    case idle                   // System inactive
    case initializing          // Loading ML model
    case cameraReady           // Ready to use
    case processing            // Processing embedding
    case authenticating        // Comparing with profile
    case registering           // Registration process
    case success               // Successful operation
    case failed                // Operation failed
    case cancelled             // Cancelled by user
}

// Use in delegate
func authenticationStateChanged(_ state: AuthState) {
    switch state {
    case .initializing:
        statusLabel.text = "Loading model..."
    case .cameraReady:
        statusLabel.text = "Camera ready"
    case .processing:
        statusLabel.text = "Processing..."
    default:
        break
    }
}
```

## User Management

### User Operations

```swift
// List all registered users
func listAllUsers() {
    do {
        let userIds = try facialAuthManager.getAllRegisteredUsers()
        print("Registered users: \(userIds.count)")
        
        for userId in userIds {
            if let profile = try facialAuthManager.getUserProfileInfo(userId: userId) {
                print("- \(profile.displayName) (\(userId))")
            }
        }
    } catch {
        print("Error: \(error)")
    }
}

// Get profile information
func getUserInfo(userId: String) {
    do {
        if let profile = try facialAuthManager.getUserProfileInfo(userId: userId) {
            print("Name: \(profile.displayName)")
            print("Created: \(profile.createdAt)")
            print("Samples: \(profile.samplesCount)")
        }
    } catch {
        print("Error getting profile: \(error)")
    }
}

// Delete user
func deleteUser(userId: String) {
    do {
        try facialAuthManager.deleteUser(userId: userId)
        print("User deleted")
    } catch {
        print("Error deleting user: \(error)")
    }
}

// Verify data integrity
func verifyUserData(userId: String) {
    do {
        let isValid = try facialAuthManager.verifyUserDataIntegrity(userId: userId)
        print(isValid ? "✅ Data is intact" : "❌ Data corrupted")
    } catch {
        print("Error verifying integrity: \(error)")
    }
}
```

## Error Handling

### Error Types

```swift
public enum AuthError: Error {
    // Configuration
    case modelNotFound, modelLoadingFailed
    
    // Permissions
    case cameraPermissionDenied
    
    // Authentication
    case userNotRegistered, faceNotDetected
    case multipleFacesDetected, similarityThresholdNotMet
    case maxAttemptsExceeded
    
    // Registration
    case registrationFailed, profileAlreadyExists
    
    // System
    case cameraUnavailable, processingFailed
}
```

### Robust Handling

```swift
func handleAuthError(_ error: AuthError) {
    switch error {
    case .cameraPermissionDenied:
        showAlert("Permissions Required", 
                 "Go to Settings to enable camera access") {
            self.openAppSettings()
        }
        
    case .faceNotDetected:
        showAlert("No Face Detected", 
                 "Make sure you're in front of the camera with good lighting")
        
    case .similarityThresholdNotMet:
        showAlert("Face Doesn't Match", 
                 "The face doesn't match the registered profile")
        
    case .maxAttemptsExceeded:
        showAlert("Blocked", 
                 "Too many attempts. Try again in 30 seconds")
        
    case .profileAlreadyExists:
        showAlert("User Exists", 
                 "This user is already registered")
        
    default:
        showAlert("Error", error.localizedDescription)
    }
}

private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
```

## Advanced Configuration

### Update Configuration

```swift
// Change configuration at runtime
func updateConfiguration() {
    let newConfig = AuthConfiguration(
        similarityThreshold: 0.90,      // Stricter
        debugMode: false,               // No logs
        trainingMode: .deep            // Maximum precision
    )
    
    facialAuthManager.updateConfiguration(newConfig)
}

// Get current configuration
func getCurrentSettings() {
    let config = facialAuthManager.getCurrentConfiguration()
    print("Threshold: \(config.similarityThreshold)")
    print("Debug: \(config.debugMode)")
    print("Mode: \(config.trainingMode.displayName)")
}
```

### Custom Preview

```swift
func setupCustomPreview() {
    guard let previewLayer = facialAuthManager.getCameraPreviewLayer() as? AVCaptureVideoPreviewLayer else {
        return
    }
    
    // Customize
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.cornerRadius = 20
    previewLayer.masksToBounds = true
    
    // Add overlay
    let overlayView = createFaceOverlay()
    cameraPreviewView.addSubview(overlayView)
}
```

## Security

### Security Architecture

- **AES-256-GCM Encryption**: All embeddings are encrypted
- **Keychain Storage**: Storage in device's secure hardware
- **Local Processing**: Zero data sent to servers
- **Embeddings Only**: Never stores images, only mathematical vectors

### Privacy

- ✅ **GDPR Compliant**: Only mathematical embeddings, not biometric data
- ✅ **Right to be Forgotten**: `deleteUser()` method available
- ✅ **No Telemetry**: No data sent to third parties
- ✅ **Open Source**: Completely auditable

### Best Practices

```swift
// Verify integrity before use
func safeAuthentication(userId: String) {
    do {
        let isValid = try facialAuthManager.verifyUserDataIntegrity(userId: userId)
        guard isValid else {
            showAlert("Data corrupted. Please re-register user.")
            return
        }
        
        facialAuthManager.authenticateUser(userId: userId, in: self)
    } catch {
        showAlert("Error verifying data")
    }
}

// Clean up on logout
func secureLogout() {
    facialAuthManager.cancel()
    // Clear temporary data if any
}
```

## Debug & Metrics

### Enable Debug

```swift
let debugConfig = AuthConfiguration(
    debugMode: true,        // Detailed logs
    logMetrics: true       // Performance metrics
)
```

### Performance Metrics

```swift
func metricsUpdated(_ metrics: AuthMetrics) {
    print("📊 Metrics:")
    print("- Time: \(metrics.processingTime * 1000)ms")
    print("- Similarity: \(metrics.similarityScore)")
    print("- Quality: \(metrics.faceQuality)")
}

func trainingProgress(_ progress: Float, epoch: Int, loss: Float, accuracy: Float) {
    print("🏋️ Epoch \(epoch): \(Int(progress * 100))% - Acc: \(String(format: "%.2f%%", accuracy * 100))")
}
```

### Debug Logs

With debug enabled you'll see logs like:

```
🚀 FacialAuth: Starting framework...
✅ ML Model loaded successfully
📹 TrueDepth camera configured
📸 Sample 1/50 captured
🏋️ Training completed - Accuracy: 94.2%
✅ User John Doe registered
🔐 Authentication successful - Similarity: 0.923
```

## Usage Examples

### Simple Login App

```swift
class LoginViewController: UIViewController {
    @IBOutlet weak var cameraPreviewView: UIView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var registerButton: UIButton!
    
    private var facialAuthManager: FacialAuthManager!
    private let userId = "main_user"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFacialAuth()
        updateUI()
    }
    
    private func setupFacialAuth() {
        let config = AuthConfiguration(similarityThreshold: 0.85, debugMode: true)
        facialAuthManager = FacialAuthManager(configuration: config)
        facialAuthManager.delegate = self
        facialAuthManager.initialize()
    }
    
    private func updateUI() {
        let isRegistered = facialAuthManager.isUserRegistered(userId: userId)
        registerButton.isEnabled = !isRegistered
        loginButton.isEnabled = isRegistered
        
        statusLabel.text = isRegistered ? 
            "User registered. Tap 'Login' to authenticate" : 
            "Tap 'Register' to get started"
    }
    
    @IBAction func registerTapped() {
        facialAuthManager.registerUser(userId: userId, displayName: "Main User", in: self)
    }
    
    @IBAction func loginTapped() {
        facialAuthManager.authenticateUser(userId: userId, in: self)
    }
}

extension LoginViewController: FacialAuthDelegate {
    func authenticationDidSucceed(userProfile: UserProfile) {
        performSegue(withIdentifier: "showMainApp", sender: nil)
    }
    
    func registrationDidSucceed(userProfile: UserProfile) {
        updateUI()
    }
    
    func authenticationDidFail(error: AuthError) {
        statusLabel.text = "Error: \(error.localizedDescription)"
    }
    
    func registrationDidFail(error: AuthError) {
        statusLabel.text = "Registration error: \(error.localizedDescription)"
    }
}
```

### Multi-user App

```swift
class UserSelectionViewController: UIViewController {
    @IBOutlet weak var usersTableView: UITableView!
    private var facialAuthManager: FacialAuthManager!
    private var users: [UserProfile] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFacialAuth()
        loadUsers()
    }
    
    private func loadUsers() {
        do {
            let userIds = try facialAuthManager.getAllRegisteredUsers()
            users = userIds.compactMap { userId in
                try? facialAuthManager.getUserProfileInfo(userId: userId)
            }
            usersTableView.reloadData()
        } catch {
            showAlert("Error loading users")
        }
    }
    
    @IBAction func addUserTapped() {
        let alert = UIAlertController(title: "New User", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name" }
        
        alert.addAction(UIAlertAction(title: "Register", style: .default) { _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            
            let userId = UUID().uuidString
            self.facialAuthManager.registerUser(userId: userId, displayName: name, in: self)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

extension UserSelectionViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath)
        let user = users[indexPath.row]
        cell.textLabel?.text = user.displayName
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = users[indexPath.row]
        facialAuthManager.authenticateUser(userId: user.userId, in: self)
    }
}
```

## License

MIT License - See [LICENSE](LICENSE) file for complete details.
