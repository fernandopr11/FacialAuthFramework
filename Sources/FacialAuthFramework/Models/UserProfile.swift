import Foundation

public struct UserProfile: Codable {
    public let userId: String
    public let createdAt: Date
    public let updatedAt: Date
    public let samplesCount: Int

    
    internal let encryptedEmbeddings: Data
    internal let version: String
    
    public init(
        userId: String,
        encryptedEmbeddings: Data,
        samplesCount: Int = 1,
        version: String = "1.0"
    ) {
        self.userId = userId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.samplesCount = samplesCount
        self.encryptedEmbeddings = encryptedEmbeddings
        self.version = version
    }
}
