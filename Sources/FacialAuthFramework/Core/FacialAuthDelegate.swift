import Foundation
import UIKit

public protocol FacialAuthDelegate: AnyObject {
    // Callbacks de autenticación
    func authenticationDidSucceed(userProfile: UserProfile)
    func authenticationDidFail(error: AuthError)
    func authenticationDidCancel()
    
    // Callbacks de registro
    func registrationDidSucceed(userProfile: UserProfile)
    func registrationDidFail(error: AuthError)
    func registrationProgress(_ progress: Float)
    
    // Callbacks de estado
    func authenticationStateChanged(_ state: AuthState)
    func cameraPermissionRequired()
    
    // Callbacks de métricas (opcional para modo debug)
    func metricsUpdated(_ metrics: AuthMetrics)
    
    // Callbacks de entrenamiento en vivo
    func trainingDidStart(mode: TrainingMode)
    func trainingProgress(_ progress: Float, epoch: Int, loss: Float, accuracy: Float)
    func trainingDidComplete(metrics: TrainingMetrics)
    func trainingDidFail(error: AuthError)
    func trainingDidCancel()
    
    // Callbacks de datos de entrenamiento
    func trainingSampleCaptured(sampleCount: Int, totalNeeded: Int)
    func trainingDataValidated(isValid: Bool, quality: Float)
}

// Extensión para hacer métodos opcionales
public extension FacialAuthDelegate {
    func registrationProgress(_ progress: Float) {}
    func authenticationStateChanged(_ state: AuthState) {}
    func cameraPermissionRequired() {}
    func metricsUpdated(_ metrics: AuthMetrics) {}
    
    // Callbacks de entrenamiento opcionales
    func trainingDidStart(mode: TrainingMode) {}
    func trainingProgress(_ progress: Float, epoch: Int, loss: Float, accuracy: Float) {}
    func trainingDidComplete(metrics: TrainingMetrics) {}
    func trainingDidFail(error: AuthError) {}
    func trainingDidCancel() {}
    func trainingSampleCaptured(sampleCount: Int, totalNeeded: Int) {}
    func trainingDataValidated(isValid: Bool, quality: Float) {}
}

// Métricas de entrenamiento
public struct TrainingMetrics: Sendable{
    public let mode: TrainingMode
    public let totalTime: TimeInterval
    public let finalAccuracy: Float
    public let finalLoss: Float
    public let epochsCompleted: Int
    public let samplesUsed: Int
    public let startTime: Date
    public let endTime: Date
    
    public init(
        mode: TrainingMode,
        totalTime: TimeInterval,
        finalAccuracy: Float,
        finalLoss: Float,
        epochsCompleted: Int,
        samplesUsed: Int,
        startTime: Date,
        endTime: Date
    ) {
        self.mode = mode
        self.totalTime = totalTime
        self.finalAccuracy = finalAccuracy
        self.finalLoss = finalLoss
        self.epochsCompleted = epochsCompleted
        self.samplesUsed = samplesUsed
        self.startTime = startTime
        self.endTime = endTime
    }
}
