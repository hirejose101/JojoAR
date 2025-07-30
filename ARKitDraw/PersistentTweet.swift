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
    
    init(id: String, text: String, latitude: Double, longitude: Double, altitude: Double?, worldPosition: SCNVector3, userId: String, timestamp: Date, isPublic: Bool) {
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
    }
    
    var worldPosition: SCNVector3 {
        return SCNVector3(worldPositionX, worldPositionY, worldPositionZ)
    }
    
    var location: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
} 