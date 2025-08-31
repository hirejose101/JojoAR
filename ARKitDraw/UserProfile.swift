import Foundation
import FirebaseFirestore

struct UserProfile: Codable {
    let id: String
    let firstName: String
    let username: String
    let dateOfBirth: Date
    let email: String
    let createdAt: Date
    let lastLoginAt: Date
    
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
              let createdAt = data["createdAt"] as? Timestamp,
              let lastLoginAt = data["lastLoginAt"] as? Timestamp else {
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
