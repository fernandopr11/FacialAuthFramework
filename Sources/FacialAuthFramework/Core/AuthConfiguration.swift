import Foundation

// MARK: - Sendable Training Mode
public enum TrainingMode: Sendable {
    case fast      // 3 epochs, 0.001 lr - Rápido
    case standard  // 8 epochs, 0.0005 lr - Estándar
    case deep      // 15 epochs, 0.0001 lr - Profundo
    
    var epochs: Int {
        switch self {
        case .fast: return 3
        case .standard: return 8
        case .deep: return 15
        }
    }
    
    var learningRate: Float {
        switch self {
        case .fast: return 0.001
        case .standard: return 0.0005
        case .deep: return 0.0001
        }
    }
    
    var displayName: String {
        switch self {
        case .fast: return "Rápido"
        case .standard: return "Estándar"
        case .deep: return "Profundo"
        }
    }
}

// MARK: - Sendable Camera Quality
public enum CameraQuality: Sendable {
    case medium
    case high
    case ultra
}

// MARK: - Sendable Auth Configuration
public struct AuthConfiguration: Sendable {
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
    
    // Configuración de entrenamiento
    public let trainingMode: TrainingMode
    public let enableLiveTraining: Bool
    public let saveTrainingMetrics: Bool
    public let maxTrainingSamples: Int
    
    public init(
        similarityThreshold: Float = 0.85,
        maxAttempts: Int = 3,
        sessionTimeout: TimeInterval = 300,
        enableTrueDepth: Bool = true,
        cameraQuality: CameraQuality = .high,
        debugMode: Bool = false,
        logMetrics: Bool = false,
        trainingMode: TrainingMode = .standard,
        enableLiveTraining: Bool = true,
        saveTrainingMetrics: Bool = false,
        maxTrainingSamples: Int = 50
    ) {
        self.similarityThreshold = similarityThreshold
        self.maxAttempts = maxAttempts
        self.sessionTimeout = sessionTimeout
        self.enableTrueDepth = enableTrueDepth
        self.cameraQuality = cameraQuality
        self.debugMode = debugMode
        self.logMetrics = logMetrics
        self.trainingMode = trainingMode
        self.enableLiveTraining = enableLiveTraining
        self.saveTrainingMetrics = saveTrainingMetrics
        self.maxTrainingSamples = maxTrainingSamples
    }
}
