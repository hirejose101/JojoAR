import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import CoreLocation
import SceneKit

class FirebaseService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let tweetsCollection = "tweets"
    private let usersCollection = "users"
    
    init() {
        // Firebase is configured in AppDelegate
    }
    
    // MARK: - Image Upload
    
    func uploadImage(_ image: UIImage, completion: @escaping (String?, Error?) -> Void) {
        guard let imageData = UIImageJPEGRepresentation(image, 0.8) else {
            completion(nil, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"]))
            return
        }
        
        let imageId = UUID().uuidString
        let imageRef = storage.reference().child("tweet_images/\(imageId).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        imageRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            imageRef.downloadURL { url, error in
                if let error = error {
                    completion(nil, error)
                } else if let downloadURL = url {
                    completion(downloadURL.absoluteString, nil)
                } else {
                    completion(nil, NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                }
            }
        }
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
    
    // MARK: - Username Fetching
    
    func fetchUsername(userId: String, completion: @escaping (String?) -> Void) {
        print("🌐 Fetching username from Firebase for userId: \(userId)")
        let userDocRef = db.collection("users").document(userId)
        
        userDocRef.getDocument { document, error in
            if let error = error {
                print("❌ Error fetching username for userId \(userId): \(error)")
                completion(nil)
                return
            }
            
            guard let document = document, document.exists else {
                print("❌ User document does not exist for userId: \(userId)")
                completion(nil)
                return
            }
            
            guard let data = document.data() else {
                print("❌ User document has no data for userId: \(userId)")
                completion(nil)
                return
            }
            
            print("📋 User document data for \(userId): \(data)")
            
            guard let username = data["username"] as? String else {
                print("❌ Username field not found or not a string for userId: \(userId)")
                completion(nil)
                return
            }
            
            print("✅ Got username from Firebase: \(username)")
            completion(username)
        }
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
            },
            "isDrawing": tweet.isDrawing,
            "drawingStrokes": tweet.drawingStrokes.map { stroke in
                return [
                    "points": stroke.points.flatMap { [$0.x, $0.y, $0.z] }, // Flatten the nested arrays
                    "color": [
                        Float(stroke.color.redComponent),
                        Float(stroke.color.greenComponent),
                        Float(stroke.color.blueComponent),
                        Float(stroke.color.alphaComponent)
                    ],
                    "width": stroke.width,
                    "timestamp": Timestamp(date: stroke.timestamp)
                ]
            },
            "hasImage": tweet.hasImage,
            "imageURL": tweet.imageURL ?? NSNull(),
            "imageWidth": tweet.imageWidth ?? NSNull(),
            "imageHeight": tweet.imageHeight ?? NSNull()
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
        
        // Parse drawing fields
        let isDrawing = data["isDrawing"] as? Bool ?? false
        let drawingStrokesData = data["drawingStrokes"] as? [[String: Any]] ?? []
        var drawingStrokes: [DrawingStroke] = []
        
        for strokeData in drawingStrokesData {
            if let stroke = drawingStrokeFromData(strokeData) {
                drawingStrokes.append(stroke)
            }
        }
        
        // Parse image fields
        let hasImage = data["hasImage"] as? Bool ?? false
        let imageURL = data["imageURL"] as? String
        let imageWidth = data["imageWidth"] as? Float
        let imageHeight = data["imageHeight"] as? Float
        
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
            color: color,
            isDrawing: isDrawing,
            drawingStrokes: drawingStrokes,
            hasImage: hasImage,
            imageURL: imageURL,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
    }
    
    private func drawingStrokeFromData(_ data: [String: Any]) -> DrawingStroke? {
        guard let pointsData = data["points"] as? [Float],
              let colorData = data["color"] as? [Float],
              let width = data["width"] as? Float,
              let timestamp = data["timestamp"] as? Timestamp else {
            return nil
        }
        
        // Convert flattened points data to SCNVector3 array
        var points: [SCNVector3] = []
        for i in stride(from: 0, to: pointsData.count, by: 3) {
            guard i + 2 < pointsData.count else { break }
            let point = SCNVector3(x: pointsData[i], y: pointsData[i + 1], z: pointsData[i + 2])
            points.append(point)
        }
        
        // Convert color data to UIColor
        guard colorData.count >= 4 else { return nil }
        let color = UIColor(
            red: CGFloat(colorData[0]),
            green: CGFloat(colorData[1]),
            blue: CGFloat(colorData[2]),
            alpha: CGFloat(colorData[3])
        )
        
        return DrawingStroke(
            points: points,
            color: color,
            width: width,
            timestamp: timestamp.dateValue()
        )
    }
    
    private func calculateDistance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to)
    }
    
    // MARK: - Friends Management
    
    private let friendsCollection = "friends"
    private let friendRequestsCollection = "friendRequests"
    
    // MARK: - Friend Requests
    
    func sendFriendRequest(toUsername: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            print("Send friend request failed: User not authenticated")
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        print("Sending friend request from \(currentUserId) to username: \(toUsername)")
        
        // First, find the user by username
        findUserByUsername(toUsername) { [weak self] targetUser, error in
            if let error = error {
                print("Find user error: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            guard let targetUser = targetUser else {
                print("Target user not found for username: \(toUsername)")
                completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"]))
                return
            }
            
            print("Found target user: \(targetUser.username) with ID: \(targetUser.id)")
            
            guard targetUser.id != currentUserId else {
                print("Cannot send friend request to self")
                completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot send friend request to yourself"]))
                return
            }
            
            // Get current user's username
            self?.fetchUsername(userId: currentUserId) { currentUsername in
                guard let currentUsername = currentUsername else {
                    completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not fetch current user's username"]))
                    return
                }
                
                // Check if friend request already exists
                self?.checkExistingFriendRequest(fromUserId: currentUserId, toUserId: targetUser.id) { existingRequest in
                    if let existingRequest = existingRequest {
                        if existingRequest.status == .pending {
                            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Friend request already sent"]))
                        } else {
                            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Friend request already exists"]))
                        }
                        return
                    }
                    
                    // Create new friend request
                    let requestId = UUID().uuidString
                    let friendRequest = FriendRequest(
                        id: requestId,
                        fromUserId: currentUserId,
                        toUserId: targetUser.id,
                        fromUsername: currentUsername,
                        toUsername: targetUser.username
                    )
                    
                    print("Creating friend request: \(friendRequest.toDictionary())")
                    
                    self?.db.collection(self?.friendRequestsCollection ?? "friendRequests").document(requestId).setData(friendRequest.toDictionary()) { error in
                        if let error = error {
                            print("Error creating friend request: \(error.localizedDescription)")
                        } else {
                            print("Successfully created friend request with ID: \(requestId)")
                        }
                        completion(error)
                    }
                }
            }
        }
    }
    
    func findUserByUsername(_ username: String, completion: @escaping (UserProfile?, Error?) -> Void) {
        db.collection(usersCollection)
            .whereField("username", isEqualTo: username)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                guard let documents = snapshot?.documents,
                      let firstDoc = documents.first else {
                    completion(nil, nil)
                    return
                }
                
                let userProfile = UserProfile.fromDocument(firstDoc)
                completion(userProfile, nil)
            }
    }
    
    func searchUsersByUsername(_ searchText: String, completion: @escaping ([UserProfile], Error?) -> Void) {
        // Check if user is authenticated
        guard let currentUserId = getCurrentUserId() else {
            completion([], NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        print("Searching for users with text: '\(searchText)' by user: \(currentUserId)")
        
        // For partial matching, we need to get all users and filter client-side
        // This is not ideal for large datasets, but works for now
        db.collection(usersCollection)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Firebase search error: \(error.localizedDescription)")
                    completion([], error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found in users collection")
                    completion([], nil)
                    return
                }
                
                print("Found \(documents.count) total users")
                
                let allUsers = documents.compactMap { UserProfile.fromDocument($0) }
                let filteredUsers = allUsers.filter { user in
                    user.username.lowercased().contains(searchText.lowercased())
                }
                
                print("Found \(filteredUsers.count) matching users")
                
                // Sort by username for better UX
                let sortedUsers = filteredUsers.sorted { $0.username < $1.username }
                completion(sortedUsers, nil)
            }
    }
    
    func checkExistingFriendRequest(fromUserId: String, toUserId: String, completion: @escaping (FriendRequest?) -> Void) {
        db.collection(friendRequestsCollection)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking existing friend request: \(error)")
                    completion(nil)
                    return
                }
                
                guard let documents = snapshot?.documents,
                      let firstDoc = documents.first else {
                    completion(nil)
                    return
                }
                
                let friendRequest = FriendRequest.fromDocument(firstDoc)
                completion(friendRequest)
            }
    }
    
    func getPendingFriendRequests(completion: @escaping ([FriendRequest], Error?) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion([], NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        print("Getting pending friend requests for user: \(currentUserId)")
        
        db.collection(friendRequestsCollection)
            .whereField("toUserId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error getting pending requests: \(error.localizedDescription)")
                    completion([], error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found for pending requests")
                    completion([], nil)
                    return
                }
                
                print("Found \(documents.count) pending friend request documents")
                for doc in documents {
                    print("Document ID: \(doc.documentID), Data: \(doc.data())")
                }
                
                let requests = documents.compactMap { FriendRequest.fromDocument($0) }
                print("Successfully parsed \(requests.count) friend requests")
                completion(requests, nil)
            }
    }
    
    // MARK: - Testing Helper Functions
    
    func clearAllFriendRequests(completion: @escaping (Error?) -> Void) {
        print("Clearing all friend requests...")
        
        db.collection(friendRequestsCollection).getDocuments { snapshot, error in
            if let error = error {
                print("Error getting friend requests to delete: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("No friend requests found to delete")
                completion(nil)
                return
            }
            
            print("Found \(documents.count) friend requests to delete")
            
            let batch = self.db.batch()
            for document in documents {
                batch.deleteDocument(document.reference)
            }
            
            batch.commit { error in
                if let error = error {
                    print("Error deleting friend requests: \(error.localizedDescription)")
                } else {
                    print("Successfully deleted all friend requests")
                }
                completion(error)
            }
        }
    }
    
    func respondToFriendRequest(requestId: String, accept: Bool, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let requestRef = db.collection(friendRequestsCollection).document(requestId)
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let requestDocument: DocumentSnapshot
            do {
                try requestDocument = transaction.getDocument(requestRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            guard let requestData = requestDocument.data(),
                  let fromUserId = requestData["fromUserId"] as? String,
                  let toUserId = requestData["toUserId"] as? String,
                  let fromUsername = requestData["fromUsername"] as? String,
                  let toUsername = requestData["toUsername"] as? String,
                  toUserId == currentUserId else {
                let error = NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid friend request"])
                errorPointer?.pointee = error
                return nil
            }
            
            let status = accept ? "accepted" : "declined"
            transaction.updateData([
                "status": status,
                "respondedAt": Timestamp(date: Date())
            ], forDocument: requestRef)
            
            // If accepted, add both users as friends
            if accept {
                let friendId1 = UUID().uuidString
                let friendId2 = UUID().uuidString
                
                // Add friend relationship in both directions
                let friend1 = Friend(id: friendId1, userId: fromUserId, username: fromUsername, firstName: requestData["fromFirstName"] as? String ?? "")
                let friend2 = Friend(id: friendId2, userId: toUserId, username: toUsername, firstName: requestData["toFirstName"] as? String ?? "")
                
                transaction.setData(friend1.toDictionary(), forDocument: self.db.collection(self.friendsCollection).document("\(fromUserId)_\(toUserId)"))
                transaction.setData(friend2.toDictionary(), forDocument: self.db.collection(self.friendsCollection).document("\(toUserId)_\(fromUserId)"))
            }
            
            return nil
        }) { (_, error) in
            completion(error)
        }
    }
    
    // MARK: - Friends List
    
    func getFriends(completion: @escaping ([Friend], Error?) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            print("❌ getFriends: User not authenticated")
            completion([], NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        print("🔍 getFriends: Fetching friends for user: \(currentUserId)")
        
        // Query for documents where the ownerId equals the current user's ID
        // Note: Removing server-side sorting to avoid index requirement - sorting on client side instead
        db.collection(friendsCollection)
            .whereField("ownerId", isEqualTo: currentUserId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ getFriends: Firebase error: \(error.localizedDescription)")
                    completion([], error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("⚠️ getFriends: No documents returned")
                    completion([], nil)
                    return
                }
                
                print("✅ getFriends: Found \(documents.count) friend documents")
                
                let friends = documents.compactMap { document in
                    let friend = Friend.fromDocument(document)
                    if friend == nil {
                        print("⚠️ Failed to parse friend document: \(document.documentID)")
                    }
                    return friend
                }
                
                print("✅ getFriends: Successfully parsed \(friends.count) friends")
                // Sort by addedAt (newest first) on client side
                let sortedFriends = friends.sorted { $0.addedAt > $1.addedAt }
                completion(sortedFriends, nil)
            }
    }
    
    func removeFriend(friendId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Remove friendship from both sides
        let friend1Ref = db.collection(friendsCollection).document("\(currentUserId)_\(friendId)")
        let friend2Ref = db.collection(friendsCollection).document("\(friendId)_\(currentUserId)")
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            transaction.deleteDocument(friend1Ref)
            transaction.deleteDocument(friend2Ref)
            return nil
        }) { (_, error) in
            completion(error)
        }
    }
    
    // MARK: - Friend Status Checking
    
    func checkIfFriends(userId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion(false)
            return
        }
        
        let friendRef = db.collection(friendsCollection).document("\(currentUserId)_\(userId)")
        friendRef.getDocument { snapshot, error in
            completion(snapshot?.exists == true)
        }
    }
    
    func checkPendingFriendRequest(toUserId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion(false)
            return
        }
        
        db.collection(friendRequestsCollection)
            .whereField("fromUserId", isEqualTo: currentUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .whereField("status", isEqualTo: "pending")
            .limit(to: 1)
            .getDocuments { snapshot, error in
                completion(snapshot?.documents.isEmpty == false)
            }
    }
    
    func checkReceivedFriendRequest(fromUserId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion(false)
            return
        }
        
        db.collection(friendRequestsCollection)
            .whereField("fromUserId", isEqualTo: fromUserId)
            .whereField("toUserId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "pending")
            .limit(to: 1)
            .getDocuments { snapshot, error in
                completion(snapshot?.documents.isEmpty == false)
            }
    }
    
    func acceptFriendRequest(requestId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let requestRef = db.collection(friendRequestsCollection).document(requestId)
        
        // First get the request details
        requestRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let data = snapshot?.data(),
                  let fromUserId = data["fromUserId"] as? String,
                  let fromUsername = data["fromUsername"] as? String,
                  let toUsername = data["toUsername"] as? String else {
                completion(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid request data"]))
                return
            }
            
            // Update the request status to accepted
            requestRef.updateData([
                "status": "accepted",
                "respondedAt": Date()
            ]) { error in
                if let error = error {
                    completion(error)
                    return
                }
                
                // Create friendship records for both users
                self?.createFriendship(fromUserId: fromUserId, toUserId: currentUserId, fromUsername: fromUsername, toUsername: toUsername, completion: completion)
            }
        }
    }
    
    private func createFriendship(fromUserId: String, toUserId: String, fromUsername: String, toUsername: String, completion: @escaping (Error?) -> Void) {
        let friend1Ref = db.collection(friendsCollection).document("\(fromUserId)_\(toUserId)")
        let friend2Ref = db.collection(friendsCollection).document("\(toUserId)_\(fromUserId)")
        
        let friend1 = Friend(
            id: "\(fromUserId)_\(toUserId)",
            userId: fromUserId,
            username: toUsername,
            firstName: "", // We'll need to fetch this
            addedAt: Date()
        )
        
        let friend2 = Friend(
            id: "\(toUserId)_\(fromUserId)",
            userId: toUserId,
            username: fromUsername,
            firstName: "", // We'll need to fetch this
            addedAt: Date()
        )
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            do {
                try transaction.setData(from: friend1, forDocument: friend1Ref)
                try transaction.setData(from: friend2, forDocument: friend2Ref)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }) { (_, error) in
            completion(error)
        }
    }
    
    // MARK: - Social Media Wall
    
    func getSocialMediaFeed(completion: @escaping ([SocialMediaPost], Error?) -> Void) {
        guard let currentUserId = getCurrentUserId() else {
            completion([], NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        print("🔍 getSocialMediaFeed: Current user ID: \(currentUserId)")
        
        // First get friends list
        getFriends { [weak self] friends, error in
            if let error = error {
                completion([], error)
                return
            }
            
            print("✅ getSocialMediaFeed: Found \(friends.count) friends")
            for friend in friends {
                print("  Friend: \(friend.username) (userId: \(friend.userId))")
            }
            
            // If no friends, return empty feed
            guard !friends.isEmpty else {
                print("⚠️ getSocialMediaFeed: No friends, returning empty feed")
                completion([], nil)
                return
            }
            
            let friendIds = friends.map { $0.userId }
            print("🔍 getSocialMediaFeed: Friend IDs to fetch tweets for: \(friendIds)")
            // Only fetch friends' tweets, not your own (you have tweet history for that)
            
            // Fetch tweets from friends only
            self?.fetchTweetsByUserIds(friendIds) { tweets, error in
                if let error = error {
                    completion([], error)
                    return
                }
                
                // Create social media posts with author info from friends only
                let posts: [SocialMediaPost] = tweets.compactMap { tweet in
                    // Find the friend who posted this tweet
                    guard let friend = friends.first(where: { $0.userId == tweet.userId }) else {
                        return nil
                    }
                    
                    return SocialMediaPost(
                        id: tweet.id,
                        tweet: tweet,
                        authorUsername: friend.username,
                        authorFirstName: friend.firstName,
                        isFromFriend: true  // All posts are from friends now
                    )
                }
                
                // Sort by timestamp (newest first)
                let sortedPosts = posts.sorted { $0.tweet.timestamp > $1.tweet.timestamp }
                completion(sortedPosts, nil)
            }
        }
    }
    
    func fetchTweetsByUserIds(_ userIds: [String], completion: @escaping ([PersistentTweet], Error?) -> Void) {
        db.collection(tweetsCollection)
            .whereField("userId", in: userIds)
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion([], error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([], nil)
                    return
                }
                
                let tweets = documents.compactMap { self?.tweetFromDocument($0) }
                completion(tweets, nil)
            }
    }
}

// MARK: - UIColor Extension
extension UIColor {
    var redComponent: CGFloat {
        var red: CGFloat = 0
        getRed(&red, green: nil, blue: nil, alpha: nil)
        return red
    }
    
    var greenComponent: CGFloat {
        var green: CGFloat = 0
        getRed(nil, green: &green, blue: nil, alpha: nil)
        return green
    }
    
    var blueComponent: CGFloat {
        var blue: CGFloat = 0
        getRed(nil, green: nil, blue: &blue, alpha: nil)
        return blue
    }
    
    var alphaComponent: CGFloat {
        var alpha: CGFloat = 0
        getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha
    }
} 
