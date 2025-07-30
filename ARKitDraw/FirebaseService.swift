import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import SceneKit

class FirebaseService {
    private let db = Firestore.firestore()
    private let tweetsCollection = "tweets"
    
    init() {
        // Firebase is configured in AppDelegate
    }
    
    // MARK: - Authentication
    
    func signInAnonymously(completion: @escaping (String?, Error?) -> Void) {
        Auth.auth().signInAnonymously { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            if let user = result?.user {
                completion(user.uid, nil)
            } else {
                completion(nil, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get user ID"]))
            }
        }
    }
    
    func getCurrentUserId() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    // MARK: - Tweet Management
    
    func saveTweet(_ tweet: PersistentTweet, completion: @escaping (Error?) -> Void) {
        let tweetData: [String: Any] = [
            "id": tweet.id,
            "text": tweet.text,
            "latitude": tweet.latitude,
            "longitude": tweet.longitude,
            "altitude": tweet.altitude ?? NSNull(),
            "worldPositionX": tweet.worldPositionX,
            "worldPositionY": tweet.worldPositionY,
            "worldPositionZ": tweet.worldPositionZ,
            "userId": tweet.userId,
            "timestamp": Timestamp(date: tweet.timestamp),
            "isPublic": tweet.isPublic
        ]
        
        db.collection(tweetsCollection).document(tweet.id).setData(tweetData) { error in
            completion(error)
        }
    }
    
    func fetchNearbyTweets(location: CLLocation, radius: Double, completion: @escaping ([PersistentTweet], Error?) -> Void) {
        // Calculate bounding box for the radius
        let latDelta = radius / 111000.0 // Approximate meters per degree latitude
        let lonDelta = radius / (111000.0 * cos(location.coordinate.latitude * .pi / 180))
        
        let minLat = location.coordinate.latitude - latDelta
        let maxLat = location.coordinate.latitude + latDelta
        let minLon = location.coordinate.longitude - lonDelta
        let maxLon = location.coordinate.longitude + lonDelta
        
        let query = db.collection(tweetsCollection)
            .whereField("latitude", isGreaterThan: minLat)
            .whereField("latitude", isLessThan: maxLat)
            .whereField("longitude", isGreaterThan: minLon)
            .whereField("longitude", isLessThan: maxLon)
            .whereField("isPublic", isEqualTo: true)
        
        query.getDocuments { snapshot, error in
            if let error = error {
                completion([], error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion([], nil)
                return
            }
            
            let tweets = documents.compactMap { document -> PersistentTweet? in
                let data = document.data()
                
                guard let id = data["id"] as? String,
                      let text = data["text"] as? String,
                      let latitude = data["latitude"] as? Double,
                      let longitude = data["longitude"] as? Double,
                      let worldPositionX = data["worldPositionX"] as? Float,
                      let worldPositionY = data["worldPositionY"] as? Float,
                      let worldPositionZ = data["worldPositionZ"] as? Float,
                      let userId = data["userId"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp,
                      let isPublic = data["isPublic"] as? Bool else {
                    return nil
                }
                
                let altitude = data["altitude"] as? Double
                let worldPosition = SCNVector3(worldPositionX, worldPositionY, worldPositionZ)
                
                return PersistentTweet(
                    id: id,
                    text: text,
                    latitude: latitude,
                    longitude: longitude,
                    altitude: altitude,
                    worldPosition: worldPosition,
                    userId: userId,
                    timestamp: timestamp.dateValue(),
                    isPublic: isPublic
                )
            }
            
            // Filter by actual distance and sort by timestamp
            let nearbyTweets = tweets.filter { tweet in
                let tweetLocation = CLLocation(latitude: tweet.latitude, longitude: tweet.longitude)
                return location.distance(from: tweetLocation) <= radius
            }.sorted { $0.timestamp > $1.timestamp }
            
            completion(nearbyTweets, nil)
        }
    }
    
    func deleteTweet(tweetId: String, completion: @escaping (Error?) -> Void) {
        db.collection(tweetsCollection).document(tweetId).delete { error in
            completion(error)
        }
    }
    
    func getUserTweets(userId: String, completion: @escaping ([PersistentTweet], Error?) -> Void) {
        let query = db.collection(tweetsCollection)
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
        
        query.getDocuments { snapshot, error in
            if let error = error {
                completion([], error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion([], nil)
                return
            }
            
            let tweets = documents.compactMap { document -> PersistentTweet? in
                let data = document.data()
                
                guard let id = data["id"] as? String,
                      let text = data["text"] as? String,
                      let latitude = data["latitude"] as? Double,
                      let longitude = data["longitude"] as? Double,
                      let worldPositionX = data["worldPositionX"] as? Float,
                      let worldPositionY = data["worldPositionY"] as? Float,
                      let worldPositionZ = data["worldPositionZ"] as? Float,
                      let userId = data["userId"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp,
                      let isPublic = data["isPublic"] as? Bool else {
                    return nil
                }
                
                let altitude = data["altitude"] as? Double
                let worldPosition = SCNVector3(worldPositionX, worldPositionY, worldPositionZ)
                
                return PersistentTweet(
                    id: id,
                    text: text,
                    latitude: latitude,
                    longitude: longitude,
                    altitude: altitude,
                    worldPosition: worldPosition,
                    userId: userId,
                    timestamp: timestamp.dateValue(),
                    isPublic: isPublic
                )
            }
            
            completion(tweets, nil)
        }
    }
} 
