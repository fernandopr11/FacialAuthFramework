import Foundation
import UIKit
import AVFoundation

@MainActor
public class FacialAuthManager {
    
    // MARK: - Properties
        public weak var delegate: FacialAuthDelegate?
        private var configuration: AuthConfiguration
        
        // Managers principales
        private var encryptionManager: EncryptionManager
        private var cameraManager: TrueDepthCameraManager
        private var faceDetectionManager: FaceDetectionManager
        private var realTimeProcessor: RealTimeProcessor
        
        // ML Components
        private var modelManager: ModelManager
        private var embeddingExtractor: FaceEmbeddingExtractor
        private var embeddingComparator: EmbeddingComparator
        private var modelTrainer: ModelTrainer
        
        // Estado actual
        private var currentState: AuthState = .idle {
            didSet {
                delegate?.authenticationStateChanged(currentState)
            }
        }
        
        // Estado de operación
        private var currentOperation: Operation?
        private var capturedImages: [UIImage] = []
        private var currentUserId: String?
        private var parentViewController: UIViewController?
        
        // MARK: - Initialization
        public init(configuration: AuthConfiguration = AuthConfiguration()) {
            self.configuration = configuration
            
            // Inicializar Security
            self.encryptionManager = EncryptionManager(debugMode: configuration.debugMode)
            
            // Inicializar ML
            self.modelManager = ModelManager(debugMode: configuration.debugMode)
            self.embeddingExtractor = FaceEmbeddingExtractor(modelManager: modelManager, debugMode: configuration.debugMode)
            self.embeddingComparator = EmbeddingComparator(debugMode: configuration.debugMode)
            
            // ✅ FIX: Pasar encryptionManager al ModelTrainer
            self.modelTrainer = ModelTrainer(
                modelManager: modelManager,
                embeddingExtractor: embeddingExtractor,
                embeddingComparator: embeddingComparator,
                encryptionManager: encryptionManager, // ✅ AGREGAR ESTE PARÁMETRO
                debugMode: configuration.debugMode
            )
            
            // Inicializar Vision
            self.cameraManager = TrueDepthCameraManager(debugMode: configuration.debugMode)
            self.faceDetectionManager = FaceDetectionManager(debugMode: configuration.debugMode)
            self.realTimeProcessor = RealTimeProcessor(
                faceDetectionManager: faceDetectionManager,
                debugMode: configuration.debugMode
            )
            
            // Configurar delegates
            setupDelegates()
        }
    
    // MARK: - Public API
    
    /// Inicializar el framework
        public func initialize() {
            currentState = .initializing
            
            if configuration.debugMode {
                print("🚀 FacialAuth: Iniciando framework con arquitectura de embeddings...")
            }
            
            Task {
                do {
                    // Cargar modelo ML
                    try modelManager.loadModel()
                    
                    // Configurar cámara
                    try await cameraManager.setupCamera()
                    
                    await MainActor.run {
                        currentState = .cameraReady
                        
                        if configuration.debugMode {
                            print("✅ FacialAuth: Framework inicializado con arquitectura correcta")
                            print("   - Modelo ML: ✅")
                            print("   - Cámara TrueDepth: ✅")
                            print("   - Detección facial: ✅")
                            print("   - Embedding extraction: ✅")
                        }
                    }
                    
                } catch {
                    await MainActor.run {
                        currentState = .failed
                        
                        if configuration.debugMode {
                            print("❌ FacialAuth: Error inicializando: \(error)")
                        }
                        
                        if let authError = error as? AuthError {
                            delegate?.authenticationDidFail(error: authError)
                        } else {
                            delegate?.authenticationDidFail(error: .modelLoadingFailed)
                        }
                    }
                }
            }
        }
        
    
    /// Registrar un nuevo usuario (REAL con cámara + entrenamiento)
    public func registerUser(userId: String, displayName: String, in viewController: UIViewController) {
        guard currentState == .cameraReady else {
            delegate?.registrationDidFail(error: .cameraUnavailable)
            return
        }
        
        // Verificar que el usuario no exista
        if encryptionManager.isUserRegistered(userId: userId) {
            delegate?.registrationDidFail(error: .profileAlreadyExists)
            return
        }
        
        currentState = .registering
        currentOperation = .registration(userId: userId, displayName: displayName)
        currentUserId = userId
        parentViewController = viewController
        capturedImages.removeAll()
        
        if configuration.debugMode {
            print("📝 FacialAuth: Iniciando registro REAL para \(displayName) (\(userId))")
        }
        
        startCameraForCapture()
    }
    
    /// Autenticar usuario existente (REAL con cámara + comparación)
    public func authenticateUser(userId: String, in viewController: UIViewController) {
        guard currentState == .cameraReady else {
            delegate?.authenticationDidFail(error: .cameraUnavailable)
            return
        }
        
        // Verificar que el usuario exista
        guard encryptionManager.isUserRegistered(userId: userId) else {
            delegate?.authenticationDidFail(error: .userNotRegistered)
            return
        }
        
        currentState = .authenticating
        currentOperation = .authentication(userId: userId)
        currentUserId = userId
        parentViewController = viewController
        
        if configuration.debugMode {
            print("🔐 FacialAuth: Iniciando autenticación REAL para \(userId)")
        }
        
        startCameraForCapture()
    }
    
    /// Cancelar operación actual
    public func cancel() {
        stopCurrentOperation()
        
        currentState = .cancelled
        delegate?.authenticationDidCancel()
        
        if configuration.debugMode {
            print("❌ FacialAuth: Operación cancelada")
        }
        
        // Volver al estado listo
        Task {
            try await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                if currentState == .cancelled {
                    currentState = .cameraReady
                }
            }
        }
    }
    
    /// Verificar si un usuario está registrado
    public func isUserRegistered(userId: String) -> Bool {
        let isRegistered = encryptionManager.isUserRegistered(userId: userId)
        
        if configuration.debugMode {
            print("🔍 FacialAuth: Usuario \(userId) \(isRegistered ? "ESTÁ REGISTRADO" : "NO ESTÁ REGISTRADO")")
        }
        
        return isRegistered
    }
    
    /// Obtener configuración actual
    public func getCurrentConfiguration() -> AuthConfiguration {
        return configuration
    }
    
    /// Actualizar configuración
    public func updateConfiguration(_ newConfiguration: AuthConfiguration) {
        self.configuration = newConfiguration
        
        // Actualizar configuraciones en componentes
        updateComponentConfigurations()
        
        if configuration.debugMode {
            print("⚙️ FacialAuth: Configuración actualizada")
        }
    }
}

// MARK: - Private Methods
private extension FacialAuthManager {
    
    func setupDelegates() {
        cameraManager.delegate = self
        realTimeProcessor.delegate = self
        faceDetectionManager.delegate = self
        modelTrainer.delegate = self
    }
    
    func updateComponentConfigurations() {
        // Configurar detección facial según configuración
        faceDetectionManager.configure(
            minFaceSize: 0.15,
            maxFaceSize: 0.8,
            minConfidence: configuration.similarityThreshold - 0.1,
            detectionFrequency: 10.0
        )
        
        // Configurar procesamiento en tiempo real
        let captureRequirements = CaptureRequirements(
            minQualityScore: configuration.similarityThreshold,
            minConfidence: configuration.similarityThreshold - 0.1,
            requireCentered: true
        )
        realTimeProcessor.enableAutoCapture(requirements: captureRequirements)
    }
    
    
    private func startCameraForCapture() {
        // Configurar processor según la operación
        updateComponentConfigurations()
        
        // ✅ CONECTAR VIDEO DELEGATE ANTES DE INICIAR
        cameraManager.setVideoDelegate(realTimeProcessor)
        
        // Iniciar cámara
        cameraManager.startSession()
        realTimeProcessor.startProcessing()
        
        if configuration.debugMode {
            print("📹 FacialAuth: Cámara iniciada para captura")
            print("📹 FacialAuth: Video delegate conectado al RealTimeProcessor")
        }
    }
    
    /// Obtener preview layer de la cámara para mostrar en UI
    public func getCameraPreviewLayer() -> CALayer? {
        return cameraManager.getPreviewLayer()
    }
    
    // ✅ AGREGAR MÉTODO PARA CONFIGURAR PREVIEW EN VIEW CONTROLLER
    public func setupCameraPreview(in viewController: UIViewController, previewView: UIView) {
        guard let previewLayer = getCameraPreviewLayer() else {
            if configuration.debugMode {
                print("❌ FacialAuth: No se pudo obtener preview layer")
            }
            return
        }
        
        // Configurar el preview layer
        previewLayer.frame = previewView.bounds
        previewView.layer.insertSublayer(previewLayer, at: 0)
        
        if configuration.debugMode {
            print("📺 FacialAuth: Preview configurado en view")
            print("   - Frame: \(previewView.bounds)")
        }
    }
    
    public func getAllRegisteredUsers() throws -> [String] {
        let userIds = try encryptionManager.getAllRegisteredUsers()
        
        if configuration.debugMode {
            print("📋 FacialAuth: \(userIds.count) usuarios registrados encontrados")
            for userId in userIds {
                print("   - \(userId)")
            }
        }
        
        return userIds
    }
    
    public func getUserProfileInfo(userId: String) throws -> UserProfile? {
        let profile = try encryptionManager.getUserProfileInfo(userId: userId)
        
        if configuration.debugMode {
            if let profile = profile {
                print("👤 FacialAuth: Perfil encontrado para \(userId)")
                print("   - Nombre: \(profile.displayName)")
                print("   - Creado: \(profile.createdAt)")
                print("   - Muestras: \(profile.samplesCount)")
            } else {
                print("❌ FacialAuth: No se encontró perfil para \(userId)")
            }
        }
        
        return profile
    }
    
    /// Verificar integridad de datos de usuario
    public func verifyUserDataIntegrity(userId: String) throws -> Bool {
        let isValid = try encryptionManager.verifyUserDataIntegrity(userId: userId)
        
        if configuration.debugMode {
            print("🔍 FacialAuth: Integridad de \(userId): \(isValid ? "✅ Válida" : "❌ Corrupta")")
        }
        
        return isValid
    }
    
    
    /// Eliminar usuario registrado
    public func deleteUser(userId: String) throws {
        try encryptionManager.deleteUser(userId: userId)
        
        if configuration.debugMode {
            print("🗑️ FacialAuth: Usuario \(userId) eliminado")
        }
    }
    
    private func stopCurrentOperation() {
        realTimeProcessor.stopProcessing()
        cameraManager.stopSession()
        
        if configuration.debugMode {
            print("🛑 Operación detenida - Imágenes capturadas: \(capturedImages.count)")
        }
        
        currentOperation = nil
        currentUserId = nil
        parentViewController = nil
    }
    
    func handleCapturedImage(_ image: UIImage) {
        guard let operation = currentOperation else { return }
        
        capturedImages.append(image)
        
        switch operation {
        case .registration(let userId, let displayName):
            handleRegistrationCapture(userId: userId, displayName: displayName, image: image)
            
        case .authentication(let userId):
            handleAuthenticationCapture(userId: userId, image: image)
        }
    }
    
    func handleRegistrationCapture(userId: String, displayName: String, image: UIImage) {
        let targetSamples = configuration.maxTrainingSamples
        let currentSamples = capturedImages.count
        
        // Notificar progreso de captura
        let progress = Float(currentSamples) / Float(targetSamples)
        delegate?.registrationProgress(progress * 0.5) // Primera mitad = captura
        
        if configuration.debugMode {
            print("📸 Registro: Muestra \(currentSamples)/\(targetSamples) capturada")
        }
        
        // ✅ BUG FIX: Verificar si tenemos suficientes muestras DESPUÉS de agregar la imagen
        if currentSamples >= targetSamples {
            stopCurrentOperation()
            
            // ✅ CRITICAL FIX: Usar capturedImages ANTES de que se limpie
            let imagesToTrain = capturedImages // Capturar referencia local
            
            if configuration.debugMode {
                print("🏋️ Iniciando entrenamiento con \(imagesToTrain.count) imágenes")
            }
            
            startTraining(userId: userId, displayName: displayName, images: imagesToTrain)
        }
    }
    
    func handleAuthenticationCapture(userId: String, image: UIImage) {
        stopCurrentOperation()
        
        currentState = .processing
        
        // Capturar referencia local al extractor
        let extractor = self.embeddingExtractor
        let comparator = self.embeddingComparator
        let encryption = self.encryptionManager
        let config = self.configuration
        
        Task {
            do {
                // Extraer embedding de la imagen capturada
                let capturedEmbedding = try await extractor.extractEmbeddings(from: image)
                
                // Obtener embedding almacenado del usuario
                guard let storedEmbedding = try encryption.getUserEmbeddings(userId: userId) else {
                    throw AuthError.userNotRegistered
                }
                
                // Comparar embeddings
                let similarity = try comparator.compareEmbeddings(capturedEmbedding, storedEmbedding)
                let isMatch = similarity.cosineSimilarity >= config.similarityThreshold
                
                await MainActor.run {
                    if isMatch {
                        // Autenticación exitosa
                        let profile = UserProfile(
                            userId: userId,
                            displayName: "Usuario \(userId)", // TODO: Obtener displayName real
                            encryptedEmbeddings: Data(), // No necesario para el resultado
                            samplesCount: 1
                        )
                        
                        currentState = .success
                        delegate?.authenticationDidSucceed(userProfile: profile)
                        
                        // Métricas de debug
                        if config.logMetrics {
                            let metrics = AuthMetrics(
                                processingTime: similarity.processingTime,
                                similarityScore: similarity.cosineSimilarity,
                                faceQuality: 0.9 // TODO: Obtener calidad real
                            )
                            delegate?.metricsUpdated(metrics)
                        }
                        
                        if config.debugMode {
                            print("✅ Autenticación exitosa - Similitud: \(String(format: "%.3f", similarity.cosineSimilarity))")
                        }
                        
                    } else {
                        currentState = .failed
                        delegate?.authenticationDidFail(error: .similarityThresholdNotMet)
                        
                        if config.debugMode {
                            print("❌ Autenticación fallida - Similitud: \(String(format: "%.3f", similarity.cosineSimilarity)) < \(config.similarityThreshold)")
                        }
                    }
                }
                
                // Volver al estado listo
                Task {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        if currentState == .success || currentState == .failed {
                            currentState = .cameraReady
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    currentState = .failed
                    
                    if config.debugMode {
                        print("❌ Error en autenticación: \(error)")
                    }
                    
                    if let authError = error as? AuthError {
                        delegate?.authenticationDidFail(error: authError)
                    } else {
                        delegate?.authenticationDidFail(error: .processingFailed)
                    }
                }
            }
        }
    }
    
    func startTraining(userId: String, displayName: String, images: [UIImage]) {
        currentState = .processing
        
        let trainer = self.modelTrainer
        let config = self.configuration
        
        // ✅ VERIFICACIÓN DE SEGURIDAD
        guard !images.isEmpty else {
            if config.debugMode {
                print("❌ ERROR: No hay imágenes para entrenar!")
            }
            
            currentState = .failed
            delegate?.registrationDidFail(error: .processingFailed)
            return
        }
        
        if config.debugMode {
            print("🏋️ Entrenamiento iniciado con \(images.count) imágenes")
        }
        
        Task {
            do {
                // Iniciar entrenamiento en vivo
                let metrics = try await trainer.trainUserModel(
                    userId: userId,
                    images: images,
                    mode: config.trainingMode
                )
                
                await MainActor.run {
                    // ✅ LIMPIAR IMÁGENES SOLO DESPUÉS DEL ÉXITO
                    capturedImages.removeAll()
                    
                    // El entrenamiento fue exitoso, crear perfil
                    let profile = UserProfile(
                        userId: userId,
                        displayName: displayName,
                        encryptedEmbeddings: Data(),
                        samplesCount: images.count
                    )
                    
                    currentState = .success
                    delegate?.registrationDidSucceed(userProfile: profile)
                    
                    if config.debugMode {
                        print("✅ Registro completo para \(displayName)")
                        print("   - Tiempo: \(String(format: "%.1f", metrics.totalTime))s")
                        print("   - Precisión: \(String(format: "%.1f", metrics.finalAccuracy * 100))%")
                    }
                }
                
                // Volver al estado listo
                Task {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        if currentState == .success {
                            currentState = .cameraReady
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    capturedImages.removeAll()
                    
                    currentState = .failed
                    
                    if config.debugMode {
                        print("❌ Error en entrenamiento: \(error)")
                    }
                    
                    if let authError = error as? AuthError {
                        delegate?.registrationDidFail(error: authError)
                    } else {
                        delegate?.registrationDidFail(error: .processingFailed)
                    }
                }
            }
        }
    }
}

// MARK: - Operation Types
private enum Operation {
    case registration(userId: String, displayName: String)
    case authentication(userId: String)
}

// MARK: - Camera Manager Delegate
extension FacialAuthManager: CameraManagerDelegate {
    
    nonisolated internal func cameraDidSetup() {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("📹 FacialAuth: Cámara configurada")
            }
        }
    }
    
    nonisolated internal func cameraDidStart() {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("▶️ FacialAuth: Cámara iniciada")
            }
        }
    }
    
    nonisolated internal func cameraDidStop() {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("⏹️ FacialAuth: Cámara detenida")
            }
        }
    }
    
    nonisolated internal func cameraDidCapturePhoto(image: UIImage, depthData: AVDepthData?) {
        let hasDepthData = depthData != nil
        
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("📸 FacialAuth: Foto capturada")
                print("   - Resolución: \(image.size)")
                print("   - Depth data: \(hasDepthData ? "SÍ" : "NO")")
            }
            
            handleCapturedImage(image)
        }
    }
    
    nonisolated internal func cameraDidFail(error: CameraError) {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("❌ FacialAuth: Error de cámara: \(error)")
            }
            
            currentState = .failed
            
            switch currentOperation {
            case .registration:
                delegate?.registrationDidFail(error: .cameraUnavailable)
            case .authentication:
                delegate?.authenticationDidFail(error: .cameraUnavailable)
            case .none:
                break
            }
        }
    }
}

// MARK: - Real Time Processor Delegate
extension FacialAuthManager: RealTimeProcessorDelegate {
    
    nonisolated internal func processingDidDetectFaces(_ faces: [FaceDetectionResult], timestamp: TimeInterval) {
        MainActor.assumeIsolated {
            // Mostrar feedback visual al usuario basado en detección
            if let bestFace = faceDetectionManager.findBestFace(from: faces) {
                let validation = faceDetectionManager.validateFaceForCapture(bestFace)
                
                // Aquí se podría actualizar UI con feedback
                if configuration.debugMode && !validation.isValid {
                    print("💡 Feedback: \(validation.feedback)")
                }
            }
        }
    }
    
    nonisolated internal func processingDidAutoCapture(image: UIImage, face: FaceDetectionResult, timestamp: TimeInterval) {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("📸 FacialAuth: Auto-captura activada")
            }
            
            handleCapturedImage(image)
        }
    }
    
    nonisolated internal func processingDidUpdateCapture(status: CaptureStatus, progress: Float) {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("🎯 Captura: \(status.message) - Progreso: \(String(format: "%.1f%%", progress * 100))")
            }
            
            // Aquí se podría actualizar UI con el estado
        }
    }
    
    nonisolated internal func processingDidFail(error: ProcessingError) {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("❌ FacialAuth: Error de procesamiento: \(error)")
            }
            
            currentState = .failed
            
            switch currentOperation {
            case .registration:
                delegate?.registrationDidFail(error: .processingFailed)
            case .authentication:
                delegate?.authenticationDidFail(error: .processingFailed)
            case .none:
                break
            }
        }
    }
}

// MARK: - Face Detection Delegate
extension FacialAuthManager: FaceDetectionDelegate {
    
    nonisolated internal func faceDetectionDidFail(error: FaceDetectionError) {
        MainActor.assumeIsolated {
            if configuration.debugMode {
                print("❌ FacialAuth: Error de detección facial: \(error)")
            }
        }
    }
}

// MARK: - Model Trainer Delegate
extension FacialAuthManager: ModelTrainerDelegate {
    
    nonisolated internal func trainingDidStart(mode: TrainingMode) {
        MainActor.assumeIsolated {
            delegate?.trainingDidStart(mode: mode)
            
            if configuration.debugMode {
                print("🏋️ FacialAuth: Entrenamiento iniciado - Modo: \(mode.displayName)")
            }
        }
    }
    
    nonisolated internal func trainingProgress(_ progress: Float, epoch: Int, loss: Float, accuracy: Float) {
        MainActor.assumeIsolated {
            // Progreso del entrenamiento es la segunda mitad (50%-100%)
            let totalProgress = 0.5 + (progress * 0.5)
            delegate?.registrationProgress(totalProgress)
            delegate?.trainingProgress(progress, epoch: epoch, loss: loss, accuracy: accuracy)
            
            if configuration.debugMode {
                print("📊 Entrenamiento: Epoch \(epoch), Loss: \(String(format: "%.4f", loss)), Acc: \(String(format: "%.2f%%", accuracy * 100))")
            }
        }
    }
    
    nonisolated internal func trainingDidComplete(metrics: TrainingMetrics) {
        MainActor.assumeIsolated {
            delegate?.trainingDidComplete(metrics: metrics)
            
            if configuration.debugMode {
                print("✅ FacialAuth: Entrenamiento completado")
            }
        }
    }
    
    nonisolated internal func trainingDidFail(error: AuthError) {
        MainActor.assumeIsolated {
            delegate?.trainingDidFail(error: error)
            
            if configuration.debugMode {
                print("❌ FacialAuth: Entrenamiento falló: \(error)")
            }
        }
    }
    
    nonisolated internal func trainingDidCancel() {
        MainActor.assumeIsolated {
            delegate?.trainingDidCancel()
            
            if configuration.debugMode {
                print("❌ FacialAuth: Entrenamiento cancelado")
            }
        }
    }
    
    nonisolated internal func trainingSampleCaptured(sampleCount: Int, totalNeeded: Int) {
        MainActor.assumeIsolated {
            delegate?.trainingSampleCaptured(sampleCount: sampleCount, totalNeeded: totalNeeded)
        }
    }
    
    nonisolated internal func trainingDataValidated(isValid: Bool, quality: Float) {
        MainActor.assumeIsolated {
            delegate?.trainingDataValidated(isValid: isValid, quality: quality)
        }
    }
}
