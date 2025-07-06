import Foundation
import UIKit
import Vision
import CoreML

internal class FaceEmbeddingExtractor {
    
    // MARK: - Properties
    private let modelManager: ModelManager
    private let debugMode: Bool
    
    // MARK: - Initialization
    internal init(modelManager: ModelManager, debugMode: Bool = false) {
        self.modelManager = modelManager
        self.debugMode = debugMode
    }
    
    // MARK: - Public Methods
    
    /// Extraer embeddings de una imagen
    internal func extractEmbeddings(from image: UIImage) async throws -> [Float] {
        if debugMode {
            print("🎯 FaceEmbeddingExtractor: Extrayendo embeddings...")
        }
        
        // Verificar que el modelo esté cargado
        guard modelManager.isModelLoaded else {
            throw ModelError.modelNotLoaded
        }
        
        // Convertir UIImage a CVPixelBuffer si es necesario
        guard let cgImage = image.cgImage else {
            throw ExtractionError.invalidImage
        }
        
        // Crear request de Vision
        let request = try createVisionRequest()
        
        // Ejecutar request
        return try await performExtraction(with: request, image: cgImage)
    }
    
    /// Extraer embeddings de múltiples imágenes
    internal func extractEmbeddingsBatch(from images: [UIImage]) async throws -> [[Float]] {
        if debugMode {
            print("🎯 FaceEmbeddingExtractor: Extrayendo embeddings de \(images.count) imágenes...")
        }
        
        var results: [[Float]] = []
        
        for (index, image) in images.enumerated() {
            do {
                let embeddings = try await extractEmbeddings(from: image)
                results.append(embeddings)
                
                if debugMode {
                    print("✅ Imagen \(index + 1)/\(images.count) procesada")
                }
            } catch {
                if debugMode {
                    print("❌ Error en imagen \(index + 1): \(error)")
                }
                throw error
            }
        }
        
        return results
    }
    
    /// Validar calidad de la imagen para extracción
    internal func validateImageQuality(_ image: UIImage) -> ImageQuality {
        // Verificar resolución mínima
        let minResolution: CGFloat = 224 // Típico para modelos de face recognition
        if image.size.width < minResolution || image.size.height < minResolution {
            return ImageQuality(score: 0.2, issues: ["Resolución muy baja"])
        }
        
        // Verificar que no sea nil
        guard let cgImage = image.cgImage else {
            return ImageQuality(score: 0.0, issues: ["Imagen corrupta"])
        }
        
        // Calcular score básico basado en resolución
        let resolutionScore = min(1.0, (image.size.width * image.size.height) / (512 * 512))
        
        var issues: [String] = []
        var score = Float(resolutionScore)
        
        // Verificar proporción de aspecto
        let aspectRatio = image.size.width / image.size.height
        if aspectRatio < 0.5 || aspectRatio > 2.0 {
            issues.append("Proporción de aspecto inadecuada")
            score *= 0.8
        }
        
        return ImageQuality(score: score, issues: issues)
    }
}

// MARK: - Private Methods
private extension FaceEmbeddingExtractor {
    
    func createVisionRequest() throws -> VNCoreMLRequest {
        let visionModel = try modelManager.getVisionModel()
        
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            if let error = error {
                if self?.debugMode == true {
                    print("❌ FaceEmbeddingExtractor: Error en Vision request: \(error)")
                }
            }
        }
        
        // Configurar request
        request.imageCropAndScaleOption = .centerCrop
        
        return request
    }
    
    func performExtraction(with request: VNCoreMLRequest, image: CGImage) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
                
                // Obtener resultados
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let firstResult = results.first else {
                    continuation.resume(throwing: ExtractionError.noEmbeddingsFound)
                    return
                }
                
                // Extraer embeddings del resultado
                let embeddings = try self.extractEmbeddingsFromResult(firstResult)
                
                if self.debugMode {
                    print("✅ FaceEmbeddingExtractor: Embeddings extraídos - dimensión: \(embeddings.count)")
                }
                
                continuation.resume(returning: embeddings)
                
            } catch {
                if self.debugMode {
                    print("❌ FaceEmbeddingExtractor: Error ejecutando Vision: \(error)")
                }
                continuation.resume(throwing: ExtractionError.visionFailed)
            }
        }
    }
    
    func extractEmbeddingsFromResult(_ result: VNCoreMLFeatureValueObservation) throws -> [Float] {
        let featureValue = result.featureValue
        
        // Intentar obtener como MLMultiArray
        if let multiArray = featureValue.multiArrayValue {
            return try convertMultiArrayToFloats(multiArray)
        }
        
        // Si no es MLMultiArray, intentar otros tipos
        throw ExtractionError.unsupportedOutputFormat
    }
    
    func convertMultiArrayToFloats(_ multiArray: MLMultiArray) throws -> [Float] {
        guard multiArray.dataType == .float32 else {
            throw ExtractionError.unsupportedDataType
        }
        
        let count = multiArray.count
        var floats: [Float] = []
        floats.reserveCapacity(count)
        
        for i in 0..<count {
            let value = multiArray[i].floatValue
            floats.append(value)
        }
        
        return floats
    }
}

// MARK: - Supporting Types
internal struct ImageQuality {
    let score: Float  // 0.0 - 1.0
    let issues: [String]
    
    var isGood: Bool {
        return score >= 0.7 && issues.isEmpty
    }
}

// MARK: - Extraction Errors
internal enum ExtractionError: Error {
    case invalidImage
    case noEmbeddingsFound
    case visionFailed
    case unsupportedOutputFormat
    case unsupportedDataType
}

extension ExtractionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Imagen inválida para procesamiento"
        case .noEmbeddingsFound:
            return "No se pudieron extraer embeddings de la imagen"
        case .visionFailed:
            return "Error en el procesamiento con Vision Framework"
        case .unsupportedOutputFormat:
            return "Formato de salida del modelo no soportado"
        case .unsupportedDataType:
            return "Tipo de datos no soportado"
        }
    }
}
