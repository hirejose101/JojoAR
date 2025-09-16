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
            "screenPositionX": tweet.screenPositionX,
            "screenPositionY": tweet.screenPositionY,
            "colorRed": tweet.colorRed,
            "colorGreen": tweet.colorGreen,
            "colorBlue": tweet.colorBlue,
            "colorAlpha": tweet.colorAlpha,
            "timestamp": Timestamp(date: tweet.timestamp),
            "isPublic": tweet.isPublic,
            "likes": tweet.likes,
            "comments": tweet.comments.map { comment in
                return [
                    "id": comment.id,
                    "text": comment.text,
                    "userId": comment.userId,
                    "username": comment.username,
                    "timestamp": Timestamp(date: comment.timestamp)
                ]
            }
        ]
        
        db.collection(tweetsCollection).document(tweet.id).setData(tweetData) { error in
            completion(error)
        }
    }
    
    func deleteTweet(tweetId: String, completion: @escaping (Error?) -> Void) {
        db.collection(tweetsCollection).document(tweetId).delete { error in
            completion(error)
        }
    }
    
    // MARK: - Like Management
    
    func toggleLike(tweetId: String, userId: String, completion: @escaping (Error?) -> Void) {
        let tweetRef = db.collection(tweetsCollection).document(tweetId)
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let tweetDocument: DocumentSnapshot
            do {
                try tweetDocument = transaction.getDocument(tweetRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard let oldData = tweetDocument.data() else {
                let error = NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tweet not found"])
                errorPointer?.pointee = error
                return nil
            }
            
            var likes = oldData["likes"] as? [String] ?? []
            
            if likes.contains(userId) {
                // Unlike: remove user from likes
                likes.removeAll { $0 == userId }
            } else {
                // Like: add user to likes
                likes.append(userId)
            }
            
            transaction.updateData(["likes": likes], forDocument: tweetRef)
            return nil
        }) { (_, error) in
            completion(error)
        }
    }
    
    // MARK: - Comment Management
    
    func addComment(tweetId: String, text: String, userId: String, username: String, completion: @escaping (Error?) -> Void) {
        let tweetRef = db.collection(tweetsCollection).document(tweetId)
        let commentId = UUID().uuidString
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let tweetDocument: DocumentSnapshot
            do {
                try tweetDocument = transaction.getDocument(tweetRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard let oldData = tweetDocument.data() else {
                let error = NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tweet not found"])
                errorPointer?.pointee = error
                return nil
            }
            
            var comments = oldData["comments"] as? [[String: Any]] ?? []
            
            let newComment: [String: Any] = [
                "id": commentId,
                "text": text,
                "userId": userId,
                "username": username,
                "timestamp": Timestamp(date: Date())
            ]
            
            comments.append(newComment)
            
            transaction.updateData(["comments": comments], forDocument: tweetRef)
            return nil
        }) { (_, error) in
            completion(error)
        }
    }
    
    func getComments(tweetId: String, completion: @escaping ([TweetComment], Error?) -> Void) {
        db.collection(tweetsCollection).document(tweetId).getDocument { document, error in
            if let error = error {
                completion([], error)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let commentsData = data["comments"] as? [[String: Any]] else {
                completion([], nil)
                return
            }
            
            var comments: [TweetComment] = []
            
            for commentData in commentsData {
                if let comment = self.commentFromData(commentData) {
                    comments.append(comment)
                }
            }
            
            // Sort comments by timestamp (newest first)
            comments.sort { $0.timestamp > $1.timestamp }
            
            completion(comments, nil)
        }
    }
    
    private func commentFromData(_ data: [String: Any]) -> TweetComment? {
        guard let id = data["id"] as? String,
              let text = data["text"] as? String,
              let userId = data["userId"] as? String,
              let username = data["username"] as? String,
              let timestamp = data["timestamp"] as? Timestamp else {
            return nil
        }
        
        return TweetComment(
            id: id,
            text: text,
            userId: userId,
            username: username,
            timestamp: timestamp.dateValue()
        )
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
        
        // Parse screen position (with fallback for old tweets)
        let screenPositionX = data["screenPositionX"] as? Float ?? 0.0
        let screenPositionY = data["screenPositionY"] as? Float ?? 0.0
        let screenPosition = CGPoint(x: CGFloat(screenPositionX), y: CGFloat(screenPositionY))
        
        // Parse color components (with fallback for old tweets)
        let colorRed = data["colorRed"] as? Float ?? 0.0
        let colorGreen = data["colorGreen"] as? Float ?? 0.0
        let colorBlue = data["colorBlue"] as? Float ?? 0.0
        let colorAlpha = data["colorAlpha"] as? Float ?? 1.0
        let color = UIColor(red: CGFloat(colorRed), green: CGFloat(colorGreen), blue: CGFloat(colorBlue), alpha: CGFloat(colorAlpha))
        
        // Parse likes and comments
        let likes = data["likes"] as? [String] ?? []
        let commentsData = data["comments"] as? [[String: Any]] ?? []
        var comments: [TweetComment] = []
        
        for commentData in commentsData {
            if let comment = commentFromData(commentData) {
                comments.append(comment)
            }
        }
        
        return PersistentTweet(
            id: id,
            text: text,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            worldPosition: worldPosition,
            userId: userId,
            timestamp: timestamp.dateValue(),
            isPublic: isPublic,
            likes: likes,
            comments: comments,
            screenPosition: screenPosition,
            color: color
        )
    }
    
    private func calculateDistance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to)
    }
} 
