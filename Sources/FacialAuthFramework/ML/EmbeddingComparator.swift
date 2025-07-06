import Foundation
import Accelerate

internal class EmbeddingComparator {
    
    // MARK: - Properties
    private let debugMode: Bool
    
    // MARK: - Initialization
    internal init(debugMode: Bool = false) {
        self.debugMode = debugMode
    }
    
    // MARK: - Public Methods
    
    /// Comparar dos embeddings usando similitud coseno
    internal func compareEmbeddings(_ embedding1: [Float], _ embedding2: [Float]) throws -> ComparisonResult {
        guard embedding1.count == embedding2.count else {
            throw ComparisonError.dimensionMismatch
        }
        
        guard !embedding1.isEmpty && !embedding2.isEmpty else {
            throw ComparisonError.emptyEmbeddings
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Calcular similitud coseno
        let cosineSimilarity = try calculateCosineSimilarity(embedding1, embedding2)
        
        // Calcular distancia euclidiana (opcional)
        let euclideanDistance = try calculateEuclideanDistance(embedding1, embedding2)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        let result = ComparisonResult(
            cosineSimilarity: cosineSimilarity,
            euclideanDistance: euclideanDistance,
            processingTime: processingTime,
            embedding1Norm: calculateNorm(embedding1),
            embedding2Norm: calculateNorm(embedding2)
        )
        
        if debugMode {
            print("🔍 EmbeddingComparator: Comparación completada")
            print("   - Similitud coseno: \(String(format: "%.4f", cosineSimilarity))")
            print("   - Distancia euclidiana: \(String(format: "%.4f", euclideanDistance))")
            print("   - Tiempo: \(String(format: "%.3f", processingTime * 1000))ms")
        }
        
        return result
    }
    
    /// Verificar si dos embeddings son de la misma persona
    internal func areFromSamePerson(_ embedding1: [Float], _ embedding2: [Float], threshold: Float = 0.85) throws -> Bool {
        let result = try compareEmbeddings(embedding1, embedding2)
        let isSame = result.cosineSimilarity >= threshold
        
        if debugMode {
            print("🔍 EmbeddingComparator: ¿Misma persona? \(isSame ? "SÍ" : "NO")")
            print("   - Similitud: \(String(format: "%.4f", result.cosineSimilarity))")
            print("   - Umbral: \(String(format: "%.4f", threshold))")
        }
        
        return isSame
    }
    
    /// Encontrar el embedding más similar de una lista
    internal func findBestMatch(for targetEmbedding: [Float], in candidates: [[Float]]) throws -> BestMatchResult? {
        guard !candidates.isEmpty else {
            return nil
        }
        
        if debugMode {
            print("🔍 EmbeddingComparator: Buscando mejor coincidencia entre \(candidates.count) candidatos...")
        }
        
        var bestSimilarity: Float = -1.0
        var bestIndex: Int = -1
        var bestResult: ComparisonResult?
        
        for (index, candidate) in candidates.enumerated() {
            let result = try compareEmbeddings(targetEmbedding, candidate)
            
            if result.cosineSimilarity > bestSimilarity {
                bestSimilarity = result.cosineSimilarity
                bestIndex = index
                bestResult = result
            }
        }
        
        guard let finalResult = bestResult, bestIndex >= 0 else {
            return nil
        }
        
        if debugMode {
            print("✅ EmbeddingComparator: Mejor coincidencia encontrada")
            print("   - Índice: \(bestIndex)")
            print("   - Similitud: \(String(format: "%.4f", bestSimilarity))")
        }
        
        return BestMatchResult(
            index: bestIndex,
            similarity: bestSimilarity,
            comparisonResult: finalResult
        )
    }
    
    /// Calcular embeddings promedio de múltiples muestras
    internal func calculateAverageEmbedding(from embeddings: [[Float]]) throws -> [Float] {
        guard !embeddings.isEmpty else {
            throw ComparisonError.emptyEmbeddings
        }
        
        let dimension = embeddings[0].count
        guard embeddings.allSatisfy({ $0.count == dimension }) else {
            throw ComparisonError.dimensionMismatch
        }
        
        var averageEmbedding = [Float](repeating: 0.0, count: dimension)
        
        // Sumar todos los embeddings
        for embedding in embeddings {
            for i in 0..<dimension {
                averageEmbedding[i] += embedding[i]
            }
        }
        
        // Dividir por el número de embeddings
        let count = Float(embeddings.count)
        for i in 0..<dimension {
            averageEmbedding[i] /= count
        }
        
        // Normalizar el resultado
        return normalizeEmbedding(averageEmbedding)
    }
    
    /// Normalizar embedding (vector unitario)
    internal func normalizeEmbedding(_ embedding: [Float]) -> [Float] {
        let norm = calculateNorm(embedding)
        guard norm > 0 else { return embedding }
        
        return embedding.map { $0 / norm }
    }
}

// MARK: - Private Methods
private extension EmbeddingComparator {
    
    func calculateCosineSimilarity(_ vec1: [Float], _ vec2: [Float]) throws -> Float {
        let dotProduct = try calculateDotProduct(vec1, vec2)
        let norm1 = calculateNorm(vec1)
        let norm2 = calculateNorm(vec2)
        
        guard norm1 > 0 && norm2 > 0 else {
            throw ComparisonError.zeroNorm
        }
        
        return dotProduct / (norm1 * norm2)
    }
    
    func calculateEuclideanDistance(_ vec1: [Float], _ vec2: [Float]) throws -> Float {
        guard vec1.count == vec2.count else {
            throw ComparisonError.dimensionMismatch
        }
        
        var sumSquaredDiffs: Float = 0.0
        for i in 0..<vec1.count {
            let diff = vec1[i] - vec2[i]
            sumSquaredDiffs += diff * diff
        }
        
        return sqrt(sumSquaredDiffs)
    }
    
    func calculateDotProduct(_ vec1: [Float], _ vec2: [Float]) throws -> Float {
        guard vec1.count == vec2.count else {
            throw ComparisonError.dimensionMismatch
        }
        
        var dotProduct: Float = 0.0
        
        // Usar Accelerate para mejor performance
        vec1.withUnsafeBufferPointer { buf1 in
            vec2.withUnsafeBufferPointer { buf2 in
                vDSP_dotpr(buf1.baseAddress!, 1, buf2.baseAddress!, 1, &dotProduct, vDSP_Length(vec1.count))
            }
        }
        
        return dotProduct
    }
    
    func calculateNorm(_ vector: [Float]) -> Float {
        var norm: Float = 0.0
        
        // Usar Accelerate para mejor performance
        vector.withUnsafeBufferPointer { buf in
            vDSP_svesq(buf.baseAddress!, 1, &norm, vDSP_Length(vector.count))
        }
        
        return sqrt(norm)
    }
}

// MARK: - Supporting Types
internal struct ComparisonResult {
    let cosineSimilarity: Float
    let euclideanDistance: Float
    let processingTime: TimeInterval
    let embedding1Norm: Float
    let embedding2Norm: Float
}

internal struct BestMatchResult {
    let index: Int
    let similarity: Float
    let comparisonResult: ComparisonResult
}

// MARK: - Comparison Errors
internal enum ComparisonError: Error {
    case dimensionMismatch
    case emptyEmbeddings
    case zeroNorm
}

extension ComparisonError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .dimensionMismatch:
            return "Las dimensiones de los embeddings no coinciden"
        case .emptyEmbeddings:
            return "Los embeddings están vacíos"
        case .zeroNorm:
            return "Vector con norma cero - no se puede normalizar"
        }
    }
}
