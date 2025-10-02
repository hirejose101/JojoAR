import UIKit
import FirebaseAuth

class SocialMediaWallViewController: UIViewController {
    
    // MARK: - Properties
    private var firebaseService: FirebaseService?
    private var socialMediaPosts: [SocialMediaPost] = []
    private var friends: [Friend] = []
    private var pendingRequests: [FriendRequest] = []
    
    // MARK: - UI Elements
    private let tableView = UITableView()
    private let addFriendButton = UIButton(type: .system)
    private let friendsButton = UIButton(type: .system)
    private let refreshControl = UIRefreshControl()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFirebase()
        loadData()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = UIColor.black
        
        // Navigation bar
        navigationItem.title = "Social Wall"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissViewController)
        )
        
        // Add friend button
        addFriendButton.setTitle("Add Friend", for: .normal)
        addFriendButton.backgroundColor = UIColor.neonGreen
        addFriendButton.setTitleColor(.white, for: .normal)
        addFriendButton.layer.cornerRadius = 8
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), for: .touchUpInside)
        addFriendButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Friends button
        friendsButton.setTitle("Friends", for: .normal)
        friendsButton.backgroundColor = UIColor.neonGreen.withAlphaComponent(0.7)
        friendsButton.setTitleColor(.white, for: .normal)
        friendsButton.layer.cornerRadius = 8
        friendsButton.addTarget(self, action: #selector(friendsTapped), for: .touchUpInside)
        friendsButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Table view
        tableView.backgroundColor = UIColor.black
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SocialMediaPostCell.self, forCellReuseIdentifier: "SocialMediaPostCell")
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(addFriendButton)
        view.addSubview(friendsButton)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            addFriendButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            addFriendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addFriendButton.widthAnchor.constraint(equalToConstant: 100),
            addFriendButton.heightAnchor.constraint(equalToConstant: 40),
            
            friendsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            friendsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            friendsButton.widthAnchor.constraint(equalToConstant: 100),
            friendsButton.heightAnchor.constraint(equalToConstant: 40),
            
            tableView.topAnchor.constraint(equalTo: addFriendButton.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupFirebase() {
        firebaseService = FirebaseService()
    }
    
    // MARK: - Data Loading
    private func loadData() {
        loadSocialMediaFeed()
        loadFriends()
        loadPendingRequests()
    }
    
    private func loadSocialMediaFeed() {
        firebaseService?.getSocialMediaFeed { [weak self] posts, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading social media feed: \(error)")
                    self?.showAlert(title: "Error", message: "Failed to load social media feed")
                } else {
                    self?.socialMediaPosts = posts
                    self?.tableView.reloadData()
                }
                self?.refreshControl.endRefreshing()
            }
        }
    }
    
    private func loadFriends() {
        firebaseService?.getFriends { [weak self] friends, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading friends: \(error)")
                } else {
                    self?.friends = friends
                    self?.updateFriendsButtonTitle()
                }
            }
        }
    }
    
    private func loadPendingRequests() {
        firebaseService?.getPendingFriendRequests { [weak self] requests, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading pending requests: \(error)")
                } else {
                    self?.pendingRequests = requests
                    self?.updateFriendsButtonTitle()
                }
            }
        }
    }
    
    private func updateFriendsButtonTitle() {
        let friendCount = friends.count
        let pendingCount = pendingRequests.count
        
        if pendingCount > 0 {
            friendsButton.setTitle("Friends (\(friendCount)) • \(pendingCount)", for: .normal)
        } else {
            friendsButton.setTitle("Friends (\(friendCount))", for: .normal)
        }
    }
    
    // MARK: - Actions
    @objc private func dismissViewController() {
        dismiss(animated: true)
    }
    
    @objc private func addFriendTapped() {
        let alert = UIAlertController(title: "Add Friend", message: "Enter username to send friend request", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Username"
        }
        
        let sendAction = UIAlertAction(title: "Send Request", style: .default) { [weak self] _ in
            guard let username = alert.textFields?.first?.text, !username.isEmpty else {
                self?.showAlert(title: "Error", message: "Please enter a username")
                return
            }
            
            self?.sendFriendRequest(toUsername: username)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(sendAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    @objc private func friendsTapped() {
        let friendsVC = FriendsViewController()
        friendsVC.friends = friends
        friendsVC.pendingRequests = pendingRequests
        friendsVC.delegate = self
        let navController = UINavigationController(rootViewController: friendsVC)
        present(navController, animated: true)
    }
    
    @objc private func refreshData() {
        loadData()
    }
    
    private func sendFriendRequest(toUsername: String) {
        firebaseService?.sendFriendRequest(toUsername: toUsername) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Error", message: error.localizedDescription)
                } else {
                    self?.showAlert(title: "Success", message: "Friend request sent to \(toUsername)")
                    self?.loadPendingRequests()
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate
extension SocialMediaWallViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return socialMediaPosts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SocialMediaPostCell", for: indexPath) as! SocialMediaPostCell
        let post = socialMediaPosts[indexPath.row]
        cell.configure(with: post)
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}

// MARK: - FriendsViewControllerDelegate
extension SocialMediaWallViewController: FriendsViewControllerDelegate {
    func friendsDidUpdate() {
        loadData()
    }
}

// MARK: - SocialMediaPostCell
class SocialMediaPostCell: UITableViewCell {
    private let authorLabel = UILabel()
    private let contentLabel = UILabel()
    private let timestampLabel = UILabel()
    private let likeButton = UIButton(type: .system)
    private let commentButton = UIButton(type: .system)
    private let containerView = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = UIColor.clear
        selectionStyle = .none
        
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        containerView.layer.cornerRadius = 12
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.neonGreen.withAlphaComponent(0.3).cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        authorLabel.font = UIFont.boldSystemFont(ofSize: 16)
        authorLabel.textColor = UIColor.neonGreen
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentLabel.font = UIFont.systemFont(ofSize: 14)
        contentLabel.textColor = UIColor.white
        contentLabel.numberOfLines = 0
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        
        timestampLabel.font = UIFont.systemFont(ofSize: 12)
        timestampLabel.textColor = UIColor.gray
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        
        likeButton.setTitle("❤️", for: .normal)
        likeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        likeButton.translatesAutoresizingMaskIntoConstraints = false
        
        commentButton.setTitle("💬", for: .normal)
        commentButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        commentButton.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(containerView)
        containerView.addSubview(authorLabel)
        containerView.addSubview(contentLabel)
        containerView.addSubview(timestampLabel)
        containerView.addSubview(likeButton)
        containerView.addSubview(commentButton)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            authorLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            authorLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            contentLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 8),
            contentLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            contentLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            timestampLabel.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 8),
            timestampLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            timestampLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            
            likeButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            likeButton.trailingAnchor.constraint(equalTo: commentButton.leadingAnchor, constant: -16),
            
            commentButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            commentButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12)
        ])
    }
    
    func configure(with post: SocialMediaPost) {
        authorLabel.text = post.isFromFriend ? "\(post.authorFirstName) (@\(post.authorUsername))" : "You"
        contentLabel.text = post.tweet.text
        timestampLabel.text = formatTimestamp(post.tweet.timestamp)
        likeButton.setTitle("❤️ \(post.tweet.likeCount)", for: .normal)
        commentButton.setTitle("💬 \(post.tweet.commentCount)", for: .normal)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - FriendsViewControllerDelegate Protocol
protocol FriendsViewControllerDelegate: AnyObject {
    func friendsDidUpdate()
}
