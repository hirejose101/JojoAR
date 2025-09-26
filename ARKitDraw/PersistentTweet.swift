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
    let screenPositionX: Float  // -1.0 to 1.0 (left to right)
    let screenPositionY: Float  // -1.0 to 1.0 (bottom to top)
    let colorRed: Float         // Red component of the color
    let colorGreen: Float       // Green component of the color
    let colorBlue: Float        // Blue component of the color
    let colorAlpha: Float       // Alpha component of the color
    let isDrawing: Bool         // True if this tweet contains a 3D drawing
    let drawingStrokes: [DrawingStroke] // Array of drawing stroke data
    let hasImage: Bool          // True if this tweet contains an image
    let imageURL: String?       // Firebase Storage URL for the image
    let imageWidth: Float?      // Original image width
    let imageHeight: Float?     // Original image height
    
    init(id: String, text: String, latitude: Double, longitude: Double, altitude: Double?, worldPosition: SCNVector3, userId: String, timestamp: Date, isPublic: Bool, likes: [String] = [], comments: [TweetComment] = [], screenPosition: CGPoint = CGPoint(x: 0, y: 0), color: UIColor = UIColor.black, isDrawing: Bool = false, drawingStrokes: [DrawingStroke] = [], hasImage: Bool = false, imageURL: String? = nil, imageWidth: Float? = nil, imageHeight: Float? = nil) {
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
        self.screenPositionX = Float(screenPosition.x)
        self.screenPositionY = Float(screenPosition.y)
        
        // Convert UIColor to components
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        self.colorRed = Float(red)
        self.colorGreen = Float(green)
        self.colorBlue = Float(blue)
        self.colorAlpha = Float(alpha)
        self.isDrawing = isDrawing
        self.drawingStrokes = drawingStrokes
        self.hasImage = hasImage
        self.imageURL = imageURL
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
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
    
    var color: UIColor {
        return UIColor(red: CGFloat(colorRed), green: CGFloat(colorGreen), blue: CGFloat(colorBlue), alpha: CGFloat(colorAlpha))
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

// MARK: - Drawing Stroke Model
struct DrawingStroke: Codable {
    let points: [SCNVector3]           // 3D points along the stroke path
    let color: UIColor                  // Stroke color
    let width: Float                    // Stroke width
    let timestamp: Date                 // When stroke was created
    
    // Codable keys
    private enum CodingKeys: String, CodingKey {
        case points
        case colorRed, colorGreen, colorBlue, colorAlpha
        case width
        case timestamp
    }
    
    init(points: [SCNVector3], color: UIColor, width: Float, timestamp: Date) {
        self.points = points
        self.color = color
        self.width = width
        self.timestamp = timestamp
    }
    
    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode points as arrays of x, y, z coordinates
        let pointData = points.map { [$0.x, $0.y, $0.z] }
        try container.encode(pointData, forKey: .points)
        
        // Encode color components
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        try container.encode(Float(red), forKey: .colorRed)
        try container.encode(Float(green), forKey: .colorGreen)
        try container.encode(Float(blue), forKey: .colorBlue)
        try container.encode(Float(alpha), forKey: .colorAlpha)
        
        try container.encode(width, forKey: .width)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    // Custom decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode points
        let pointData = try container.decode([[Float]].self, forKey: .points)
        points = pointData.map { SCNVector3($0[0], $0[1], $0[2]) }
        
        // Decode color
        let red = try container.decode(Float.self, forKey: .colorRed)
        let green = try container.decode(Float.self, forKey: .colorGreen)
        let blue = try container.decode(Float.self, forKey: .colorBlue)
        let alpha = try container.decode(Float.self, forKey: .colorAlpha)
        color = UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
        
        width = try container.decode(Float.self, forKey: .width)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
} 