import Foundation
import Security

internal class KeychainManager {
    
    // MARK: - Properties
    private let service: String
    private let accessGroup: String?
    
    // MARK: - Initialization
    internal init(service: String = "FacialAuthFramework", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }
    
    // MARK: - Public Methods
    
    /// Guardar perfil de usuario encriptado
    internal func saveUserProfile(_ profile: UserProfile) throws {
        let profileData = try JSONEncoder().encode(profile)
        try saveData(profileData, for: profileKey(userId: profile.userId))
    }
    
    /// Obtener perfil de usuario
    internal func getUserProfile(userId: String) throws -> UserProfile? {
        guard let data = try getData(for: profileKey(userId: userId)) else {
            return nil
        }
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }
    
    /// Verificar si existe un perfil de usuario
    internal func profileExists(for userId: String) -> Bool {
        do {
            return try getData(for: profileKey(userId: userId)) != nil
        } catch {
            return false
        }
    }
    
    /// Eliminar perfil de usuario
    internal func deleteUserProfile(userId: String) throws {
        try deleteData(for: profileKey(userId: userId))
    }
    
    /// Listar todos los usuarios registrados
    internal func getAllUserIds() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return []
            }
            throw KeychainError.queryFailed(status)
        }
        
        guard let items = result as? [[String: Any]] else {
            return []
        }
        
        let userIds = items.compactMap { item -> String? in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix("profile_") else {
                return nil
            }
            return String(account.dropFirst(8)) // Remover "profile_"
        }
        
        return userIds
    }
    
    /// Limpiar todos los datos del framework
    internal func clearAllData() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Private Methods
private extension KeychainManager {
    
    /// Generar llave para el perfil del usuario
    func profileKey(userId: String) -> String {
        return "profile_\(userId)"
    }
    
    /// Guardar datos en Keychain
    func saveData(_ data: Data, for key: String) throws {
        // Primero intentar actualizar si ya existe
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if updateStatus == errSecItemNotFound {
            // Si no existe, crear nuevo
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            
            if addStatus != errSecSuccess {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.updateFailed(updateStatus)
        }
    }
    
    /// Obtener datos del Keychain
    func getData(for key: String) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.queryFailed(status)
        }
        
        return result as? Data
    }
    
    /// Eliminar datos del Keychain
    func deleteData(for key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Keychain Errors
internal enum KeychainError: Error {
    case saveFailed(OSStatus)
    case updateFailed(OSStatus)
    case queryFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataCorrupted
}

extension KeychainError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Error guardando en Keychain: \(status)"
        case .updateFailed(let status):
            return "Error actualizando Keychain: \(status)"
        case .queryFailed(let status):
            return "Error consultando Keychain: \(status)"
        case .deleteFailed(let status):
            return "Error eliminando de Keychain: \(status)"
        case .dataCorrupted:
            return "Datos corruptos en Keychain"
        }
    }
}
