import Foundation
import Vision
import UIKit
import AVFoundation

@MainActor
internal class FaceDetectionManager {
    
    // MARK: - Properties
    private let debugMode: Bool
    private var isDetecting = false
    
    // Delegate para callbacks
    internal weak var delegate: FaceDetectionDelegate?
    
    // Estado de detección
    private var lastDetectionTime: TimeInterval = 0
    private var detectionThreshold: TimeInterval = 0.1 // 100ms entre detecciones
    
    // Configuración de calidad
    private var minFaceSize: CGFloat = 0.15 // 15% del frame
    private var maxFaceSize: CGFloat = 0.8  // 80% del frame
    private var minConfidence: Float = 0.7
    
    // MARK: - Initialization
    internal init(debugMode: Bool = false) {
        self.debugMode = debugMode
    }
    
    // MARK: - Public Methods
    
    /// Detectar rostros en una imagen
    internal func detectFaces(in image: UIImage) async throws -> [FaceDetectionResult] {
        guard let cgImage = image.cgImage else {
            throw FaceDetectionError.invalidImage
        }
        
        return try await detectFaces(in: cgImage)
    }
    
    /// Detectar rostros en CGImage
    internal func detectFaces(in cgImage: CGImage) async throws -> [FaceDetectionResult] {
        if debugMode {
            print("👤 FaceDetection: Analizando imagen...")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = self.processFaceObservations(observations, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
                continuation.resume(returning: results)
            }
            
            // Configurar request
            request.revision = VNDetectFaceRectanglesRequestRevision3
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: FaceDetectionError.detectionFailed)
            }
        }
    }
    
    /// Detectar rostros en tiempo real (para video frames)
    internal func detectFacesRealTime(in pixelBuffer: CVPixelBuffer) async -> [FaceDetectionResult] {
        // Control de frecuencia
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastDetectionTime >= detectionThreshold else {
            return []
        }
        lastDetectionTime = currentTime
        
        guard !isDetecting else {
            return []
        }
        
        isDetecting = true
        
        do {
            let results = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[FaceDetectionResult], Error>) in
                let request = VNDetectFaceRectanglesRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let observations = request.results as? [VNFaceObservation] else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    let imageSize = CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    )
                    
                    let results = self.processFaceObservations(observations, imageSize: imageSize)
                    continuation.resume(returning: results)
                }
                
                // Configuración optimizada para tiempo real
                request.revision = VNDetectFaceRectanglesRequestRevision3
                
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
                
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: FaceDetectionError.detectionFailed)
                }
            }
            
            isDetecting = false
            
            // Notificar resultados en tiempo real - CORRECCIÓN AQUÍ
            if !results.isEmpty {
                // Crear una copia local para evitar data races
                let resultsCopy = results
                delegate?.faceDetectionDidUpdate(faces: resultsCopy)
            }
            
            return results
            
        } catch {
            isDetecting = false
            
            if debugMode {
                print("❌ FaceDetection: Error en detección tiempo real: \(error)")
            }
            
            return []
        }
    }
    
    /// Validar si un rostro es adecuado para captura
    internal func validateFaceForCapture(_ face: FaceDetectionResult) -> FaceValidationResult {
        var issues: [String] = []
        var qualityScore: Float = 1.0
        
        // Verificar tamaño del rostro
        let faceArea = face.boundingBox.width * face.boundingBox.height
        
        if faceArea < minFaceSize {
            issues.append("Rostro muy pequeño - acércate más")
            qualityScore *= 0.5
        } else if faceArea > maxFaceSize {
            issues.append("Rostro muy grande - aléjate un poco")
            qualityScore *= 0.7
        }
        
        // Verificar confianza
        if face.confidence < minConfidence {
            issues.append("Detección poco confiable")
            qualityScore *= 0.6
        }
        
        // Verificar posición central
        let center = CGPoint(
            x: face.boundingBox.midX,
            y: face.boundingBox.midY
        )
        
        let distanceFromCenter = sqrt(
            pow(center.x - 0.5, 2) + pow(center.y - 0.5, 2)
        )
        
        if distanceFromCenter > 0.3 {
            issues.append("Centra tu rostro en la pantalla")
            qualityScore *= 0.8
        }
        
        // Verificar landmarks si están disponibles
        if let landmarks = face.landmarks {
            qualityScore *= validateLandmarks(landmarks)
        }
        
        let isGoodForCapture = issues.isEmpty && qualityScore >= 0.8
        
        return FaceValidationResult(
            isValid: isGoodForCapture,
            qualityScore: qualityScore,
            issues: issues,
            centeredness: Float(1.0 - distanceFromCenter),
            faceSize: Float(faceArea)
        )
    }
    
    /// Encontrar el mejor rostro de múltiples detecciones
    internal func findBestFace(from faces: [FaceDetectionResult]) -> FaceDetectionResult? {
        guard !faces.isEmpty else { return nil }
        
        if faces.count == 1 {
            return faces.first
        }
        
        // Encontrar el rostro con mejor score combinado
        let bestFace = faces.max { face1, face2 in
            let validation1 = validateFaceForCapture(face1)
            let validation2 = validateFaceForCapture(face2)
            
            return validation1.qualityScore < validation2.qualityScore
        }
        
        return bestFace
    }
    
    /// Configurar thresholds de detección
    internal func configure(
        minFaceSize: CGFloat? = nil,
        maxFaceSize: CGFloat? = nil,
        minConfidence: Float? = nil,
        detectionFrequency: TimeInterval? = nil
    ) {
        if let minSize = minFaceSize {
            self.minFaceSize = minSize
        }
        if let maxSize = maxFaceSize {
            self.maxFaceSize = maxSize
        }
        if let confidence = minConfidence {
            self.minConfidence = confidence
        }
        if let frequency = detectionFrequency {
            self.detectionThreshold = 1.0 / frequency
        }
        
        if debugMode {
            print("⚙️ FaceDetection: Configuración actualizada")
            print("   - Min face size: \(self.minFaceSize)")
            print("   - Max face size: \(self.maxFaceSize)")
            print("   - Min confidence: \(self.minConfidence)")
            print("   - Detection frequency: \(1.0 / detectionThreshold) Hz")
        }
    }
}

// MARK: - Private Methods
private extension FaceDetectionManager {
    
    func processFaceObservations(_ observations: [VNFaceObservation], imageSize: CGSize) -> [FaceDetectionResult] {
        var results: [FaceDetectionResult] = []
        
        for observation in observations {
            // Convertir coordenadas normalizadas a píxeles
            let boundingBox = VNImageRectForNormalizedRect(observation.boundingBox, Int(imageSize.width), Int(imageSize.height))
            
            // Normalizar boundingBox a 0-1
            let normalizedBox = CGRect(
                x: boundingBox.origin.x / imageSize.width,
                y: boundingBox.origin.y / imageSize.height,
                width: boundingBox.width / imageSize.width,
                height: boundingBox.height / imageSize.height
            )
            
            let result = FaceDetectionResult(
                boundingBox: normalizedBox,
                confidence: observation.confidence,
                landmarks: observation.landmarks.map { SendableFaceLandmarks(from: $0) }
            )
            
            results.append(result)
        }
        
        if debugMode && !results.isEmpty {
            print("👤 FaceDetection: \(results.count) rostro(s) detectado(s)")
            for (index, result) in results.enumerated() {
                print("   - Rostro \(index + 1): confianza=\(String(format: "%.2f", result.confidence))")
            }
        }
        
        return results
    }
    
    func validateLandmarks(_ landmarks: SendableFaceLandmarks) -> Float {
        var score: Float = 1.0
        
        // Verificar si los ojos están visibles y abiertos
        if let leftEye = landmarks.leftEye,
           let rightEye = landmarks.rightEye {
            
            // Los ojos deben tener suficientes puntos
            if leftEye.count < 6 || rightEye.count < 6 {
                score *= 0.8
            }
        } else {
            score *= 0.7 // Penalizar si no se detectan ojos
        }
        
        // Verificar nariz
        if landmarks.nose == nil {
            score *= 0.8
        }
        
        // Verificar boca
        if landmarks.outerLips == nil {
            score *= 0.8
        }
        
        return score
    }
}

// MARK: - Face Detection Delegate
internal protocol FaceDetectionDelegate: AnyObject {
    @MainActor func faceDetectionDidUpdate(faces: [FaceDetectionResult])
    @MainActor func faceDetectionDidFail(error: FaceDetectionError)
}

internal extension FaceDetectionDelegate {
    func faceDetectionDidUpdate(faces: [FaceDetectionResult]) {}
    func faceDetectionDidFail(error: FaceDetectionError) {}
}

// MARK: - Data Models
internal struct FaceDetectionResult: Sendable {
    let boundingBox: CGRect  // Coordenadas normalizadas 0-1
    let confidence: Float
    let landmarks: SendableFaceLandmarks?
    
    // Propiedades de conveniencia
    var center: CGPoint {
        return CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }
    
    var area: CGFloat {
        return boundingBox.width * boundingBox.height
    }
}

// MARK: - Sendable Wrapper for VNFaceLandmarks2D
internal struct SendableFaceLandmarks: Sendable {
    let leftEye: [CGPoint]?
    let rightEye: [CGPoint]?
    let nose: [CGPoint]?
    let outerLips: [CGPoint]?
    let innerLips: [CGPoint]?
    let leftEyebrow: [CGPoint]?
    let rightEyebrow: [CGPoint]?
    let faceContour: [CGPoint]?
    
    init(from landmarks: VNFaceLandmarks2D) {
        self.leftEye = landmarks.leftEye?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.rightEye = landmarks.rightEye?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.nose = landmarks.nose?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.outerLips = landmarks.outerLips?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.innerLips = landmarks.innerLips?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.leftEyebrow = landmarks.leftEyebrow?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.rightEyebrow = landmarks.rightEyebrow?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.faceContour = landmarks.faceContour?.normalizedPoints.map { CGPoint(x: $0.x, y: $0.y) }
    }
}

internal struct FaceValidationResult: Sendable {
    let isValid: Bool
    let qualityScore: Float  // 0.0 - 1.0
    let issues: [String]
    let centeredness: Float  // Qué tan centrado está
    let faceSize: Float      // Tamaño relativo del rostro
    
    var feedback: String {
        if isValid {
            return "¡Perfecto! Mantén la posición"
        } else if let firstIssue = issues.first {
            return firstIssue
        } else {
            return "Posiciona tu rostro correctamente"
        }
    }
}

// MARK: - Face Detection Errors
internal enum FaceDetectionError: Error, Sendable {
    case invalidImage
    case detectionFailed
    case noFacesDetected
    case multipleFacesDetected
    case poorQuality
}

extension FaceDetectionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Imagen inválida para detección facial"
        case .detectionFailed:
            return "Error en la detección facial"
        case .noFacesDetected:
            return "No se detectaron rostros en la imagen"
        case .multipleFacesDetected:
            return "Se detectaron múltiples rostros"
        case .poorQuality:
            return "Calidad de detección insuficiente"
        }
    }
}
