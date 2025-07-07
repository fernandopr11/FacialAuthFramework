import Foundation
import CoreML
import Vision

internal class ModelManager {
    
    // MARK: - Properties
    private var visionModel: VNCoreMLModel?
    private var mlModel: MLModel?
    private let modelName: String
    private let debugMode: Bool
    
    // MARK: - Initialization
    internal init(modelName: String = "FaceRecognitionModel", debugMode: Bool = false) {
        self.modelName = modelName
        self.debugMode = debugMode
    }
    
    // MARK: - Public Methods
    
    /// Cargar el modelo desde el bundle
    internal func loadModel() throws {
        if debugMode {
            print("🤖 ModelManager: Cargando modelo \(modelName)...")
        }
        
        // En Swift Package, usar Bundle.module para acceder a los recursos
        // Intentar primero con .mlmodelc (compilado) y después con .mlmodel (original)
        var modelURL: URL?
        
        // Primero intentar con la extensión compilada
        modelURL = Bundle.module.url(forResource: modelName, withExtension: "mlmodelc")
        
        // Si no existe, intentar con la extensión original
        if modelURL == nil {
            modelURL = Bundle.module.url(forResource: modelName, withExtension: "mlmodel")
        }
        
        guard let finalModelURL = modelURL else {
            if debugMode {
                print("❌ ModelManager: Modelo no encontrado en bundle")
                // Debug adicional para ver qué recursos están disponibles
                print("📂 Recursos disponibles en bundle:")
                if let resourcePath = Bundle.module.resourcePath {
                    print("   Path: \(resourcePath)")
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                        print("   Contenidos: \(contents)")
                    } catch {
                        print("   Error listando contenidos: \(error)")
                    }
                }
            }
            throw ModelError.modelNotFound
        }
        
        do {
            // Cargar modelo CoreML
            let loadedMLModel = try MLModel(contentsOf: finalModelURL)
            self.mlModel = loadedMLModel
            
            // Crear VNCoreMLModel para usar con Vision
            self.visionModel = try VNCoreMLModel(for: loadedMLModel)
            
            if debugMode {
                print("✅ ModelManager: Modelo cargado exitosamente")
                print("📊 ModelManager: URL del modelo: \(finalModelURL)")
                print("📊 ModelManager: Descripción del modelo:")
                print("   - Input: \(loadedMLModel.modelDescription.inputDescriptionsByName)")
                print("   - Output: \(loadedMLModel.modelDescription.outputDescriptionsByName)")
            }
            
        } catch {
            if debugMode {
                print("❌ ModelManager: Error cargando modelo: \(error)")
            }
            throw ModelError.modelLoadingFailed
        }
    }
    
    /// Verificar si el modelo está cargado
    internal var isModelLoaded: Bool {
        return visionModel != nil && mlModel != nil
    }
    
    /// Obtener el modelo para usar con Vision
    internal func getVisionModel() throws -> VNCoreMLModel {
        guard let model = visionModel else {
            throw ModelError.modelNotLoaded
        }
        return model
    }
    
    /// Obtener el modelo CoreML original
    internal func getCoreMLModel() throws -> MLModel {
        guard let model = mlModel else {
            throw ModelError.modelNotLoaded
        }
        return model
    }
    
    /// Obtener información del modelo
    internal func getModelInfo() throws -> ModelInfo {
        guard let model = mlModel else {
            throw ModelError.modelNotLoaded
        }
        
        let description = model.modelDescription
        let metadata = description.metadata
        
        return ModelInfo(
            name: modelName,
            version: metadata[MLModelMetadataKey.versionString] as? String ?? "Unknown",
            author: metadata[MLModelMetadataKey.author] as? String ?? "Unknown",
            description: metadata[MLModelMetadataKey.description] as? String ?? "Face Recognition Model",
            inputNames: Array(description.inputDescriptionsByName.keys),
            outputNames: Array(description.outputDescriptionsByName.keys)
        )
    }
    
    /// Recargar el modelo
    internal func reloadModel() throws {
        visionModel = nil
        mlModel = nil
        try loadModel()
        
        if debugMode {
            print("🔄 ModelManager: Modelo recargado exitosamente")
        }
    }
}

// MARK: - Model Info
internal struct ModelInfo {
    let name: String
    let version: String
    let author: String
    let description: String
    let inputNames: [String]
    let outputNames: [String]
}

// MARK: - Model Errors
internal enum ModelError: Error {
    case modelNotFound
    case modelNotLoaded
    case modelLoadingFailed
    case invalidInput
    case predictionFailed
}

extension ModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Modelo de reconocimiento facial no encontrado"
        case .modelNotLoaded:
            return "Modelo no está cargado en memoria"
        case .modelLoadingFailed:
            return "Error al cargar el modelo CoreML"
        case .invalidInput:
            return "Datos de entrada inválidos para el modelo"
        case .predictionFailed:
            return "Error al ejecutar predicción del modelo"
        }
    }
}
