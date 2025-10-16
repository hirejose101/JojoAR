import Foundation
import FirebaseFirestore

enum FriendStatus: String, Codable {
    case none
    case friends
    case requestSent
    case requestReceived
}

struct UserProfile: Codable {
    let id: String
    let firstName: String
    let username: String
    let dateOfBirth: Date
    let email: String
    let createdAt: Date
    let lastLoginAt: Date
    var friendStatus: FriendStatus = .none
    
    init(id: String, firstName: String, username: String, dateOfBirth: Date, email: String) {
        self.id = id
        self.firstName = firstName
        self.username = username
        self.dateOfBirth = dateOfBirth
        self.email = email
        self.createdAt = Date()
        self.lastLoginAt = Date()
    }
    
    // Convert to Firestore dictionary
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "firstName": firstName,
            "username": username,
            "dateOfBirth": Timestamp(date: dateOfBirth),
            "email": email,
            "createdAt": Timestamp(date: createdAt),
            "lastLoginAt": Timestamp(date: lastLoginAt)
        ]
    }
    
    // Create from Firestore document
    static func fromDocument(_ document: DocumentSnapshot) -> UserProfile? {
        guard let data = document.data(),
              let id = data["id"] as? String,
              let firstName = data["firstName"] as? String,
              let username = data["username"] as? String,
              let dateOfBirth = data["dateOfBirth"] as? Timestamp,
              let email = data["email"] as? String,
              let _ = data["createdAt"] as? Timestamp,
              let _ = data["lastLoginAt"] as? Timestamp else {
            return nil
        }
        
        return UserProfile(
            id: id,
            firstName: firstName,
            username: username,
            dateOfBirth: dateOfBirth.dateValue(),
            email: email
        )
    }
}

// MARK: - Friends Data Models

struct FriendRequest: Codable, Identifiable {
    let id: String
    let fromUserId: String
    let toUserId: String
    let fromUsername: String
    let toUsername: String
    let status: FriendRequestStatus
    let createdAt: Date
    let respondedAt: Date?
    
    init(id: String, fromUserId: String, toUserId: String, fromUsername: String, toUsername: String, status: FriendRequestStatus = .pending, createdAt: Date = Date(), respondedAt: Date? = nil) {
        self.id = id
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.fromUsername = fromUsername
        self.toUsername = toUsername
        self.status = status
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
    
    // Convert to Firestore dictionary
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "fromUsername": fromUsername,
            "toUsername": toUsername,
            "status": status.rawValue,
            "createdAt": Timestamp(date: createdAt),
            "respondedAt": respondedAt != nil ? Timestamp(date: respondedAt!) : NSNull()
        ]
    }
    
    // Create from Firestore document
    static func fromDocument(_ document: DocumentSnapshot) -> FriendRequest? {
        guard let data = document.data(),
              let id = data["id"] as? String,
              let fromUserId = data["fromUserId"] as? String,
              let toUserId = data["toUserId"] as? String,
              let fromUsername = data["fromUsername"] as? String,
              let toUsername = data["toUsername"] as? String,
              let statusString = data["status"] as? String,
              let status = FriendRequestStatus(rawValue: statusString),
              let createdAt = data["createdAt"] as? Timestamp else {
            return nil
        }
        
        let respondedAt = data["respondedAt"] as? Timestamp
        return FriendRequest(
            id: id,
            fromUserId: fromUserId,
            toUserId: toUserId,
            fromUsername: fromUsername,
            toUsername: toUsername,
            status: status,
            createdAt: createdAt.dateValue(),
            respondedAt: respondedAt?.dateValue()
        )
    }
}

enum FriendRequestStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
}

struct Friend: Codable, Identifiable {
    let id: String
    let ownerId: String  // The user who owns this friend record
    let userId: String   // The friend's user ID
    let username: String
    let firstName: String
    let addedAt: Date
    
    init(id: String, ownerId: String, userId: String, username: String, firstName: String, addedAt: Date = Date()) {
        self.id = id
        self.ownerId = ownerId
        self.userId = userId
        self.username = username
        self.firstName = firstName
        self.addedAt = addedAt
    }
    
    // Convert to Firestore dictionary
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "ownerId": ownerId,
            "userId": userId,
            "username": username,
            "firstName": firstName,
            "addedAt": Timestamp(date: addedAt)
        ]
    }
    
    // Create from Firestore document
    static func fromDocument(_ document: DocumentSnapshot) -> Friend? {
        guard let data = document.data(),
              let id = data["id"] as? String,
              let ownerId = data["ownerId"] as? String,
              let userId = data["userId"] as? String,
              let username = data["username"] as? String,
              let firstName = data["firstName"] as? String,
              let addedAt = data["addedAt"] as? Timestamp else {
            return nil
        }
        
        return Friend(
            id: id,
            ownerId: ownerId,
            userId: userId,
            username: username,
            firstName: firstName,
            addedAt: addedAt.dateValue()
        )
    }
}

struct SocialMediaPost: Codable, Identifiable {
    let id: String
    let tweet: PersistentTweet
    let authorUsername: String
    let authorFirstName: String
    let isFromFriend: Bool
    
    init(id: String, tweet: PersistentTweet, authorUsername: String, authorFirstName: String, isFromFriend: Bool = false) {
        self.id = id
        self.tweet = tweet
        self.authorUsername = authorUsername
        self.authorFirstName = authorFirstName
        self.isFromFriend = isFromFriend
    }
}
