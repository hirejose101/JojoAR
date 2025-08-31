import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import SceneKit

class FirebaseService {
    private let db = Firestore.firestore()
    private let tweetsCollection = "tweets"
    private let usersCollection = "users"
    
    init() {
        // Firebase is configured in AppDelegate
    }
    
    // MARK: - Authentication
    
    // Anonymous authentication removed - only registered users allowed
    
    func getCurrentUserId() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    // MARK: - User Registration & Authentication
    
    func createUserAccount(email: String, password: String, firstName: String, username: String, dateOfBirth: Date, completion: @escaping (Bool, Error?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            guard let user = result?.user else {
                completion(false, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create user"]))
                return
            }
            
            // Create user profile in Firestore
            let userData: [String: Any] = [
                "id": user.uid,
                "firstName": firstName,
                "username": username,
                "dateOfBirth": Timestamp(date: dateOfBirth),
                "email": email,
                "createdAt": Timestamp(date: Date()),
                "lastLoginAt": Timestamp(date: Date())
            ]
            
            self?.db.collection(self?.usersCollection ?? "users").document(user.uid).setData(userData) { error in
                if let error = error {
                    completion(false, error)
                } else {
                    completion(true, nil)
                }
            }
        }
    }
    
    func signInUser(email: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            guard let user = result?.user else {
                completion(false, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to sign in"]))
                return
            }
            
            // Update last login time
            let userData: [String: Any] = [
                "lastLoginAt": Timestamp(date: Date())
            ]
            
            self?.db.collection(self?.usersCollection ?? "users").document(user.uid).updateData(userData) { error in
                if let error = error {
                    print("Warning: Failed to update last login time: \(error)")
                }
                completion(true, nil)
            }
        }
    }
    
    func getUserProfile(userId: String, completion: @escaping (UserProfile?, Error?) -> Void) {
        db.collection(usersCollection).document(userId).getDocument { document, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let document = document, document.exists else {
                completion(nil, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User profile not found"]))
                return
            }
            
            let userProfile = UserProfile.fromDocument(document)
            completion(userProfile, nil)
        }
    }
    
    func signOut() -> Error? {
        do {
            try Auth.auth().signOut()
            return nil
        } catch {
            return error
        }
    }
    
    func isUserSignedIn() -> Bool {
        return Auth.auth().currentUser != nil
    }
    
    func getCurrentUser() -> UserProfile? {
        guard let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous else {
            return nil
        }
        
        // For now, return nil - you can implement synchronous profile fetching if needed
        return nil
    }
    
    // MARK: - Tweet Management
    
    func saveTweet(_ tweet: PersistentTweet, completion: @escaping (Error?) -> Void) {
        let tweetData: [String: Any] = [
            "id": tweet.id,
            "text": tweet.text,
            "userId": tweet.userId,
            "latitude": tweet.latitude,
            "longitude": tweet.longitude,
            "altitude": tweet.altitude ?? NSNull(),
            "worldPositionX": tweet.worldPositionX,
            "worldPositionY": tweet.worldPositionY,
            "worldPositionZ": tweet.worldPositionZ,
            "timestamp": Timestamp(date: tweet.timestamp),
            "isPublic": tweet.isPublic
        ]
        
        db.collection(tweetsCollection).document(tweet.id).setData(tweetData) { error in
            completion(error)
        }
    }
    
    func fetchNearbyTweets(latitude: Double, longitude: Double, radius: Double, completion: @escaping ([PersistentTweet], Error?) -> Void) {
        // For now, fetch all tweets and filter by distance
        // In production, you'd use Firestore's GeoPoint and geohashing
        db.collection(tweetsCollection).getDocuments { [weak self] snapshot, error in
            if let error = error {
                completion([], error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion([], nil)
                return
            }
            
            var nearbyTweets: [PersistentTweet] = []
            
            for document in documents {
                if let tweet = self?.tweetFromDocument(document) {
                    let distance = self?.calculateDistance(
                        from: CLLocation(latitude: latitude, longitude: longitude),
                        to: CLLocation(latitude: tweet.latitude, longitude: tweet.longitude)
                    ) ?? Double.infinity
                    
                    if distance <= radius {
                        nearbyTweets.append(tweet)
                    }
                }
            }
            
            completion(nearbyTweets, nil)
        }
    }
    
    private func tweetFromDocument(_ document: DocumentSnapshot) -> PersistentTweet? {
        guard let data = document.data(),
              let id = data["id"] as? String,
              let text = data["text"] as? String,
              let userId = data["userId"] as? String,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double,
              let worldPositionX = data["worldPositionX"] as? Float,
              let worldPositionY = data["worldPositionY"] as? Float,
              let worldPositionZ = data["worldPositionZ"] as? Float,
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
    
    private func calculateDistance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to)
    }
} 
