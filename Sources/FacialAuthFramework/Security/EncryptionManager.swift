import Foundation

internal class EncryptionManager {
    
    // MARK: - Properties
    private let secureEmbeddingManager: SecureEmbeddingManager
    private let keychainManager: KeychainManager
    private let debugMode: Bool
    
    // MARK: - Initialization
    internal init(debugMode: Bool = false) {
        self.secureEmbeddingManager = SecureEmbeddingManager()
        self.keychainManager = KeychainManager()
        self.debugMode = debugMode
    }
    
    // MARK: - Public Methods
    
    /// Guardar perfil de usuario con embeddings encriptados
    internal func saveUserProfile(userId: String, displayName: String, embeddings: [Float]) throws {
        if debugMode {
            print("🔐 EncryptionManager: Guardando perfil para \(displayName) (\(userId))")
        }
        
        // Encriptar embeddings
        let encryptedEmbeddings = try secureEmbeddingManager.encryptEmbeddings(embeddings)
        
        // ✅ USAR EL DISPLAY NAME REAL, NO "Usuario {userId}"
        let profile = UserProfile(
            userId: userId,
            displayName: displayName, // ✅ ESTE ES EL CAMBIO IMPORTANTE
            encryptedEmbeddings: encryptedEmbeddings,
            samplesCount: 1
        )
        
        // Guardar en Keychain
        try keychainManager.saveUserProfile(profile)
        
        if debugMode {
            print("✅ EncryptionManager: Perfil guardado exitosamente")
        }
    }
    
    /// Obtener y desencriptar embeddings del usuario
    internal func getUserEmbeddings(userId: String) throws -> [Float]? {
        if debugMode {
            print("🔍 EncryptionManager: Buscando perfil para \(userId)")
        }
        
        // Obtener perfil del Keychain
        guard let profile = try keychainManager.getUserProfile(userId: userId) else {
            if debugMode {
                print("❌ EncryptionManager: Perfil no encontrado")
            }
            return nil
        }
        
        // Desencriptar embeddings
        let embeddings = try secureEmbeddingManager.decryptEmbeddings(profile.encryptedEmbeddings)
        
        if debugMode {
            print("✅ EncryptionManager: Embeddings desencriptados exitosamente")
        }
        
        return embeddings
    }
    
    /// Verificar si un usuario está registrado
    internal func isUserRegistered(userId: String) -> Bool {
        let exists = keychainManager.profileExists(for: userId)
        
        if debugMode {
            print("🔍 EncryptionManager: Usuario \(userId) \(exists ? "EXISTE" : "NO EXISTE")")
        }
        
        return exists
    }
    
    /// Actualizar embeddings de un usuario existente
    internal func updateUserEmbeddings(userId: String, newEmbeddings: [Float]) throws {
        if debugMode {
            print("🔄 EncryptionManager: Actualizando embeddings para \(userId)")
        }
        
        // Verificar que el usuario existe
        guard let existingProfile = try keychainManager.getUserProfile(userId: userId) else {
            throw SecurityError.userNotFound
        }
        
        // Encriptar nuevos embeddings
        let encryptedEmbeddings = try secureEmbeddingManager.encryptEmbeddings(newEmbeddings)
        
        // Actualizar perfil (creamos uno nuevo con los datos actualizados)
        let updatedProfile = UserProfile(
            userId: userId,
            displayName: existingProfile.displayName, // Mantener el nombre
            encryptedEmbeddings: encryptedEmbeddings,
            samplesCount: existingProfile.samplesCount + 1
        )
        
        // Guardar perfil actualizado
        try keychainManager.saveUserProfile(updatedProfile)
        
        if debugMode {
            print("✅ EncryptionManager: Embeddings actualizados exitosamente")
        }
    }
    
    /// Eliminar usuario y todos sus datos
    internal func deleteUser(userId: String) throws {
        if debugMode {
            print("🗑️ EncryptionManager: Eliminando usuario \(userId)")
        }
        
        try keychainManager.deleteUserProfile(userId: userId)
        
        if debugMode {
            print("✅ EncryptionManager: Usuario eliminado exitosamente")
        }
    }
    
    /// Obtener lista de todos los usuarios registrados
    internal func getAllRegisteredUsers() throws -> [String] {
        let userIds = try keychainManager.getAllUserIds()
        
        if debugMode {
            print("📋 EncryptionManager: \(userIds.count) usuarios registrados")
        }
        
        return userIds
    }
    
    /// Limpiar todos los datos del framework
    internal func clearAllData() throws {
        if debugMode {
            print("🧹 EncryptionManager: Limpiando todos los datos")
        }
        
        try keychainManager.clearAllData()
        
        if debugMode {
            print("✅ EncryptionManager: Todos los datos eliminados")
        }
    }
    
    /// Verificar integridad de los datos de un usuario
    internal func verifyUserDataIntegrity(userId: String) throws -> Bool {
        guard let profile = try keychainManager.getUserProfile(userId: userId) else {
            return false
        }
        
        // Intentar desencriptar para verificar integridad
        do {
            _ = try secureEmbeddingManager.decryptEmbeddings(profile.encryptedEmbeddings)
            
            if debugMode {
                print("✅ EncryptionManager: Integridad verificada para \(userId)")
            }
            
            return true
        } catch {
            if debugMode {
                print("❌ EncryptionManager: Datos corruptos para \(userId)")
            }
            
            return false
        }
    }
    
    /// Obtener información del perfil sin desencriptar embeddings
    internal func getUserProfileInfo(userId: String) throws -> UserProfile? {
        return try keychainManager.getUserProfile(userId: userId)
    }
}

// MARK: - Security Errors
internal enum SecurityError: Error {
    case userNotFound
    case dataCorrupted
    case encryptionFailed
    case decryptionFailed
    case keychainError
}

extension SecurityError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "Usuario no encontrado en el sistema"
        case .dataCorrupted:
            return "Datos de usuario corruptos"
        case .encryptionFailed:
            return "Error en el proceso de encriptación"
        case .decryptionFailed:
            return "Error en el proceso de desencriptación"
        case .keychainError:
            return "Error de acceso al almacenamiento seguro"
        }
    }
}
