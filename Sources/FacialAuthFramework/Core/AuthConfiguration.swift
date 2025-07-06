import Foundation

public struct AuthConfiguration {
    // Configuración de autenticación
    public let similarityThreshold: Float
    public let maxAttempts: Int
    public let sessionTimeout: TimeInterval
    
    // Configuración de cámara
    public let enableTrueDepth: Bool
    public let cameraQuality: CameraQuality
    
    // Configuración de debugging
    public let debugMode: Bool
    public let logMetrics: Bool
    
    public init(
        similarityThreshold: Float = 0.85,
        maxAttempts: Int = 3,
        sessionTimeout: TimeInterval = 300,
        enableTrueDepth: Bool = true,
        cameraQuality: CameraQuality = .high,
        debugMode: Bool = false,
        logMetrics: Bool = false
    ) {
        self.similarityThreshold = similarityThreshold
        self.maxAttempts = maxAttempts
        self.sessionTimeout = sessionTimeout
        self.enableTrueDepth = enableTrueDepth
        self.cameraQuality = cameraQuality
        self.debugMode = debugMode
        self.logMetrics = logMetrics
    }
}

public enum CameraQuality {
    case medium
    case high
    case ultra
}
