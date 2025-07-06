import Foundation
import AVFoundation
import UIKit
import Vision

@MainActor
internal class RealTimeProcessor: NSObject {
    
    // MARK: - Properties
    private let faceDetectionManager: FaceDetectionManager
    private let debugMode: Bool
    
    // Delegate para callbacks
    internal weak var delegate: RealTimeProcessorDelegate?
    
    // Estado del procesamiento
    private var isProcessing = false
    private var processingQueue = DispatchQueue(label: "com.facialauth.realtime", qos: .userInitiated)
    
    // Buffer circular para frames
    private var frameBuffer: [CVPixelBuffer] = []
    private let maxBufferSize = 3
    private var bufferIndex = 0
    
    // Control de frecuencia
    private var lastProcessTime: TimeInterval = 0
    private let processingInterval: TimeInterval = 0.1 // 10 FPS
    
    // Estado de captura automática
    private var autoCapture = false
    private var captureRequirements: CaptureRequirements
    private var consecutiveGoodFrames = 0
    private let requiredConsecutiveFrames = 5
    
    // Métricas de performance
    private var frameCount = 0
    private var droppedFrames = 0
    private var averageProcessingTime: TimeInterval = 0
    
    // MARK: - Initialization
    internal init(
        faceDetectionManager: FaceDetectionManager,
        debugMode: Bool = false
    ) {
        self.faceDetectionManager = faceDetectionManager
        self.debugMode = debugMode
        self.captureRequirements = CaptureRequirements()
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Iniciar procesamiento en tiempo real
    internal func startProcessing() {
        if debugMode {
            print("🎬 RealTimeProcessor: Iniciando procesamiento...")
        }
        
        isProcessing = true
        frameCount = 0
        droppedFrames = 0
        consecutiveGoodFrames = 0
        
        delegate?.processingDidStart()
    }
    
    /// Detener procesamiento
    internal func stopProcessing() {
        if debugMode {
            print("⏹️ RealTimeProcessor: Deteniendo procesamiento...")
            printPerformanceMetrics()
        }
        
        isProcessing = false
        frameBuffer.removeAll()
        
        delegate?.processingDidStop()
    }
    
    /// Procesar frame de video (ahora recibe CVPixelBuffer directamente)
    internal func processVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard isProcessing else { return }
        
        // Control de frecuencia
        guard timestamp - lastProcessTime >= processingInterval else {
            droppedFrames += 1
            return
        }
        lastProcessTime = timestamp
        
        frameCount += 1
        
        // Procesar en background
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.processPixelBuffer(pixelBuffer, timestamp: timestamp)
            }
        }
    }
    
    /// Configurar captura automática
    internal func enableAutoCapture(requirements: CaptureRequirements) {
        self.captureRequirements = requirements
        self.autoCapture = true
        self.consecutiveGoodFrames = 0
        
        if debugMode {
            print("🤖 RealTimeProcessor: Captura automática habilitada")
            print("   - Min quality: \(requirements.minQualityScore)")
            print("   - Min confidence: \(requirements.minConfidence)")
            print("   - Consecutive frames: \(requiredConsecutiveFrames)")
        }
    }
    
    /// Deshabilitar captura automática
    internal func disableAutoCapture() {
        self.autoCapture = false
        self.consecutiveGoodFrames = 0
        
        if debugMode {
            print("🔴 RealTimeProcessor: Captura automática deshabilitada")
        }
    }
    
    /// Capturar frame actual manualmente
    internal func captureCurrentFrame() -> UIImage? {
        guard let currentBuffer = getCurrentBuffer() else {
            return nil
        }
        
        return pixelBufferToUIImage(currentBuffer)
    }
    
    /// Obtener métricas de performance
    internal func getPerformanceMetrics() -> ProcessingMetrics {
        let currentTime = CACurrentMediaTime()
        let totalTime = currentTime - (currentTime - lastProcessTime)
        let fps = frameCount > 0 && totalTime > 0 ? Double(frameCount) / totalTime : 0
        let dropRate = frameCount > 0 ? Double(droppedFrames) / Double(frameCount + droppedFrames) : 0
        
        return ProcessingMetrics(
            framesProcessed: frameCount,
            droppedFrames: droppedFrames,
            averageProcessingTime: averageProcessingTime,
            currentFPS: fps,
            dropRate: dropRate
        )
    }
}

// MARK: - Private Methods
private extension RealTimeProcessor {
    
    func processPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        let processingStart = CACurrentMediaTime()
        
        // Agregar al buffer circular
        addToBuffer(pixelBuffer)
        
        // Detección facial asíncrona
        Task { @MainActor in
            do {
                let faces = await faceDetectionManager.detectFacesRealTime(in: pixelBuffer)
                
                // Calcular tiempo de procesamiento
                let processingTime = CACurrentMediaTime() - processingStart
                updateAverageProcessingTime(processingTime)
                
                // Procesar resultados
                await processDetectionResults(faces, pixelBuffer: pixelBuffer, timestamp: timestamp)
                
            } catch {
                if debugMode {
                    print("❌ RealTimeProcessor: Error procesando frame: \(error)")
                }
                delegate?.processingDidFail(error: .processingFailed)
            }
        }
    }
    
    func processDetectionResults(_ faces: [FaceDetectionResult], pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) async {
        // Actualizar delegate con resultados
        delegate?.processingDidDetectFaces(faces, timestamp: timestamp)
        
        // Manejar captura automática
        if autoCapture {
            await handleAutoCapture(faces: faces, pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
        
        // Debug info
        if debugMode && !faces.isEmpty {
            let bestFace = faceDetectionManager.findBestFace(from: faces)
            if let face = bestFace {
                let validation = faceDetectionManager.validateFaceForCapture(face)
                print("👤 Frame \(frameCount): \(faces.count) rostro(s), calidad: \(String(format: "%.2f", validation.qualityScore))")
            }
        }
    }
    
    func handleAutoCapture(faces: [FaceDetectionResult], pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) async {
        guard let bestFace = faceDetectionManager.findBestFace(from: faces) else {
            consecutiveGoodFrames = 0
            delegate?.processingDidUpdateCapture(status: .noFaceDetected, progress: 0)
            return
        }
        
        let validation = faceDetectionManager.validateFaceForCapture(bestFace)
        
        // Verificar si cumple requisitos
        let meetsRequirements = validation.qualityScore >= captureRequirements.minQualityScore &&
                               bestFace.confidence >= captureRequirements.minConfidence &&
                               validation.isValid
        
        if meetsRequirements {
            consecutiveGoodFrames += 1
            
            let progress = Float(consecutiveGoodFrames) / Float(requiredConsecutiveFrames)
            delegate?.processingDidUpdateCapture(status: .validating, progress: progress)
            
            if consecutiveGoodFrames >= requiredConsecutiveFrames {
                // Capturar automáticamente
                if let image = pixelBufferToUIImage(pixelBuffer) {
                    consecutiveGoodFrames = 0
                    delegate?.processingDidAutoCapture(image: image, face: bestFace, timestamp: timestamp)
                    
                    if debugMode {
                        print("📸 RealTimeProcessor: Captura automática exitosa")
                    }
                }
            }
        } else {
            consecutiveGoodFrames = max(0, consecutiveGoodFrames - 1)
            
            let status: CaptureStatus
            if validation.qualityScore < captureRequirements.minQualityScore {
                status = .poorQuality
            } else if bestFace.confidence < captureRequirements.minConfidence {
                status = .lowConfidence
            } else {
                status = .notCentered
            }
            
            delegate?.processingDidUpdateCapture(status: status, progress: 0)
        }
    }
    
    func addToBuffer(_ pixelBuffer: CVPixelBuffer) {
        if frameBuffer.count < maxBufferSize {
            frameBuffer.append(pixelBuffer)
        } else {
            frameBuffer[bufferIndex] = pixelBuffer
            bufferIndex = (bufferIndex + 1) % maxBufferSize
        }
    }
    
    func getCurrentBuffer() -> CVPixelBuffer? {
        guard !frameBuffer.isEmpty else { return nil }
        
        let index = bufferIndex > 0 ? bufferIndex - 1 : frameBuffer.count - 1
        return frameBuffer[index]
    }
    
    func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func updateAverageProcessingTime(_ newTime: TimeInterval) {
        if averageProcessingTime == 0 {
            averageProcessingTime = newTime
        } else {
            // Media móvil simple
            averageProcessingTime = (averageProcessingTime * 0.9) + (newTime * 0.1)
        }
    }
    
    func printPerformanceMetrics() {
        let metrics = getPerformanceMetrics()
        print("📊 RealTimeProcessor: Métricas de performance")
        print("   - Frames procesados: \(metrics.framesProcessed)")
        print("   - Frames descartados: \(metrics.droppedFrames)")
        print("   - FPS promedio: \(String(format: "%.1f", metrics.currentFPS))")
        print("   - Tasa de descarte: \(String(format: "%.1f%%", metrics.dropRate * 100))")
        print("   - Tiempo procesamiento: \(String(format: "%.2f", metrics.averageProcessingTime * 1000))ms")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension RealTimeProcessor: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Extraer pixel buffer inmediatamente en el contexto del callback
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let timestamp = CACurrentMediaTime()
        
        // Crear wrapper sendable
        let sendableBuffer = SendablePixelBuffer(pixelBuffer: pixelBuffer, timestamp: timestamp)
        
        // Pasar el wrapper al contexto MainActor
        Task { @MainActor in
            processVideoFrame(sendableBuffer.pixelBuffer, timestamp: sendableBuffer.timestamp)
        }
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        Task { @MainActor in
            droppedFrames += 1
            
            if debugMode {
                print("⚠️ RealTimeProcessor: Frame descartado por el sistema")
            }
        }
    }
}

// MARK: - Real Time Processor Delegate
internal protocol RealTimeProcessorDelegate: AnyObject {
    func processingDidStart()
    func processingDidStop()
    func processingDidDetectFaces(_ faces: [FaceDetectionResult], timestamp: TimeInterval)
    func processingDidUpdateCapture(status: CaptureStatus, progress: Float)
    func processingDidAutoCapture(image: UIImage, face: FaceDetectionResult, timestamp: TimeInterval)
    func processingDidFail(error: ProcessingError)
}

internal extension RealTimeProcessorDelegate {
    func processingDidStart() {}
    func processingDidStop() {}
    func processingDidDetectFaces(_ faces: [FaceDetectionResult], timestamp: TimeInterval) {}
    func processingDidUpdateCapture(status: CaptureStatus, progress: Float) {}
    func processingDidAutoCapture(image: UIImage, face: FaceDetectionResult, timestamp: TimeInterval) {}
    func processingDidFail(error: ProcessingError) {}
}

// MARK: - Sendable Wrapper
internal struct SendablePixelBuffer: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
    
    init(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
    }
}

// MARK: - Data Models
internal struct CaptureRequirements {
    let minQualityScore: Float
    let minConfidence: Float
    let requireCentered: Bool
    
    internal init(
        minQualityScore: Float = 0.8,
        minConfidence: Float = 0.7,
        requireCentered: Bool = true
    ) {
        self.minQualityScore = minQualityScore
        self.minConfidence = minConfidence
        self.requireCentered = requireCentered
    }
}

internal enum CaptureStatus {
    case noFaceDetected
    case poorQuality
    case lowConfidence
    case notCentered
    case validating
    case ready
    
    var message: String {
        switch self {
        case .noFaceDetected:
            return "Posiciona tu rostro frente a la cámara"
        case .poorQuality:
            return "Mejora la iluminación"
        case .lowConfidence:
            return "Mantén el rostro estable"
        case .notCentered:
            return "Centra tu rostro"
        case .validating:
            return "Validando... mantén la posición"
        case .ready:
            return "¡Listo para capturar!"
        }
    }
}

internal struct ProcessingMetrics {
    let framesProcessed: Int
    let droppedFrames: Int
    let averageProcessingTime: TimeInterval
    let currentFPS: Double
    let dropRate: Double
}

// MARK: - Processing Errors
internal enum ProcessingError: Error {
    case processingFailed
    case bufferOverflow
    case invalidFrame
}

extension ProcessingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .processingFailed:
            return "Error procesando frame de video"
        case .bufferOverflow:
            return "Buffer de frames saturado"
        case .invalidFrame:
            return "Frame de video inválido"
        }
    }
}
