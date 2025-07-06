import Foundation

public struct UserProfile: Codable {
    public let userId: String
    public let displayName: String
    public let createdAt: Date
    public let updatedAt: Date
    public let samplesCount: Int
    
    // Datos internos (no expuestos)
    internal let encryptedEmbeddings: Data
    internal let version: String
    
    public init(
        userId: String,
        displayName: String,
        encryptedEmbeddings: Data,
        samplesCount: Int = 1,
        version: String = "1.0"
    ) {
        self.userId = userId
        self.displayName = displayName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.samplesCount = samplesCount
        self.encryptedEmbeddings = encryptedEmbeddings
        self.version = version
    }
}
