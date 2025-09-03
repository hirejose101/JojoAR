import Foundation
import SceneKit
import CoreLocation

struct PersistentTweet: Codable {
    let id: String
    let text: String
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let worldPositionX: Float
    let worldPositionY: Float
    let worldPositionZ: Float
    let userId: String
    let timestamp: Date
    let isPublic: Bool
    let likes: [String] // Array of user IDs who liked this tweet
    let comments: [TweetComment] // Array of comments
    
    init(id: String, text: String, latitude: Double, longitude: Double, altitude: Double?, worldPosition: SCNVector3, userId: String, timestamp: Date, isPublic: Bool, likes: [String] = [], comments: [TweetComment] = []) {
        self.id = id
        self.text = text
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.worldPositionX = worldPosition.x
        self.worldPositionY = worldPosition.y
        self.worldPositionZ = worldPosition.z
        self.userId = userId
        self.timestamp = timestamp
        self.isPublic = isPublic
        self.likes = likes
        self.comments = comments
    }
    
    var worldPosition: SCNVector3 {
        return SCNVector3(worldPositionX, worldPositionY, worldPositionZ)
    }
    
    var location: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    var likeCount: Int {
        return likes.count
    }
    
    var commentCount: Int {
        return comments.count
    }
    
    func isLikedBy(userId: String) -> Bool {
        return likes.contains(userId)
    }
}

// MARK: - Tweet Comment Model
struct TweetComment: Codable, Identifiable {
    let id: String
    let text: String
    let userId: String
    let username: String
    let timestamp: Date
    
    init(id: String, text: String, userId: String, username: String, timestamp: Date) {
        self.id = id
        self.text = text
        self.userId = userId
        self.username = username
        self.timestamp = timestamp
    }
} 