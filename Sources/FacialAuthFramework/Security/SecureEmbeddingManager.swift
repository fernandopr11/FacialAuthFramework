import Foundation
import CryptoKit

internal class SecureEmbeddingManager {
    
    // MARK: - Properties
    private let keySize: Int = 32 // 256 bits para AES-256
    private let nonceSize: Int = 12 // 96 bits para AES-GCM
    
    // MARK: - Public Methods
    
    /// Encriptar embeddings faciales
    internal func encryptEmbeddings(_ embeddings: [Float]) throws -> Data {
        // Convertir array de floats a Data
        let embeddingsData = try floatsToData(embeddings)
        
        // Generar llave simétrica
        let symmetricKey = SymmetricKey(size: .bits256)
        
        // Encriptar usando AES-GCM
        let sealedBox = try AES.GCM.seal(embeddingsData, using: symmetricKey)
        
        // Combinar llave + datos encriptados
        let keyData = symmetricKey.withUnsafeBytes { Data($0) }
        let encryptedData = sealedBox.combined!
        
        // Formato: [keySize][key][encryptedData]
        var result = Data()
        result.append(keyData)
        result.append(encryptedData)
        
        return result
    }
    
    /// Desencriptar embeddings faciales
    internal func decryptEmbeddings(_ encryptedData: Data) throws -> [Float] {
        guard encryptedData.count > keySize else {
            throw EncryptionError.invalidData
        }
        
        // Extraer llave
        let keyData = encryptedData.prefix(keySize)
        let symmetricKey = SymmetricKey(data: keyData)
        
        // Extraer datos encriptados
        let encryptedEmbeddings = encryptedData.dropFirst(keySize)
        
        // Desencriptar
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedEmbeddings)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        // Convertir Data de vuelta a array de floats
        return try dataToFloats(decryptedData)
    }
    
    /// Generar hash seguro para verificación de integridad
    internal func generateHash(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Verificar integridad de datos
    internal func verifyIntegrity(data: Data, expectedHash: String) -> Bool {
        let currentHash = generateHash(for: data)
        return currentHash == expectedHash
    }
}

// MARK: - Private Methods
private extension SecureEmbeddingManager {
    
    /// Convertir array de floats a Data
    func floatsToData(_ floats: [Float]) throws -> Data {
        guard !floats.isEmpty else {
            throw EncryptionError.emptyData
        }
        
        return floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
    
    /// Convertir Data a array de floats
    func dataToFloats(_ data: Data) throws -> [Float] {
        guard data.count % MemoryLayout<Float>.size == 0 else {
            throw EncryptionError.invalidData
        }
        
        let floatCount = data.count / MemoryLayout<Float>.size
        var floats = [Float](repeating: 0, count: floatCount)
        
        _ = floats.withUnsafeMutableBufferPointer { buffer in
            data.copyBytes(to: buffer)
        }
        
        return floats
    }
}

// MARK: - Encryption Errors
internal enum EncryptionError: Error {
    case invalidData
    case emptyData
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
}

extension EncryptionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Datos inválidos para encriptación"
        case .emptyData:
            return "No hay datos para encriptar"
        case .encryptionFailed:
            return "Error en el proceso de encriptación"
        case .decryptionFailed:
            return "Error en el proceso de desencriptación"
        case .keyGenerationFailed:
            return "Error generando llave de encriptación"
        }
    }
}
