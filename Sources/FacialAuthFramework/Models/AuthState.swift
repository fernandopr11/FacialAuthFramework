import Foundation

public enum AuthState {
    case idle
    case initializing
    case cameraReady
    case scanning
    case processing
    case authenticating
    case registering
    case success
    case failed
    case cancelled
}

public struct AuthMetrics {
    public let processingTime: TimeInterval
    public let similarityScore: Float
    public let faceQuality: Float
    public let timestamp: Date
    
    public init(
        processingTime: TimeInterval,
        similarityScore: Float,
        faceQuality: Float,
        timestamp: Date = Date()
    ) {
        self.processingTime = processingTime
        self.similarityScore = similarityScore
        self.faceQuality = faceQuality
        self.timestamp = timestamp
    }
}
