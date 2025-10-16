import UIKit

class FriendsViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: FriendsViewControllerDelegate?
    var friends: [Friend] = []
    var pendingRequests: [FriendRequest] = []
    private var firebaseService: FirebaseService?
    private var searchResults: [UserProfile] = []
    private var isSearching = false
    
    // MARK: - UI Elements
    private let segmentedControl = UISegmentedControl(items: ["Friends", "Requests", "Add Friend"])
    private let tableView = UITableView()
    private let searchBar = UISearchBar()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFirebase()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadPendingRequests()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = UIColor.black
        
        // Navigation bar
        navigationItem.title = "Friends"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissViewController)
        )
        
        // Add clear requests button for testing
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear All",
            style: .plain,
            target: self,
            action: #selector(clearAllRequestsTapped)
        )
        
        // Segmented control
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.backgroundColor = UIColor.neonGreen.withAlphaComponent(0.3)
        segmentedControl.selectedSegmentTintColor = UIColor.neonGreen
        segmentedControl.setTitleTextAttributes([NSAttributedString.Key.foregroundColor: UIColor.white], for: .normal)
        segmentedControl.setTitleTextAttributes([NSAttributedString.Key.foregroundColor: UIColor.black], for: .selected)
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        
        // Search bar
        searchBar.placeholder = "Search by username..."
        searchBar.backgroundColor = UIColor.black
        searchBar.barTintColor = UIColor.black
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.isHidden = true
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        // Style search bar text field
        if let textField = searchBar.value(forKey: "searchField") as? UITextField {
            textField.backgroundColor = UIColor.darkGray
            textField.textColor = UIColor.white
            textField.attributedPlaceholder = NSAttributedString(
                string: "Search by username...",
                attributes: [NSAttributedString.Key.foregroundColor: UIColor.lightGray]
            )
        }
        
        // Table view
        tableView.backgroundColor = UIColor.black
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(FriendCell.self, forCellReuseIdentifier: "FriendCell")
        tableView.register(FriendRequestCell.self, forCellReuseIdentifier: "FriendRequestCell")
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(segmentedControl)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40),
            
            searchBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupFirebase() {
        firebaseService = FirebaseService()
        loadPendingRequests()
    }
    
    private func loadPendingRequests() {
        firebaseService?.getPendingFriendRequests { [weak self] requests, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error loading pending requests: \(error.localizedDescription)")
                } else {
                    self?.pendingRequests = requests
                    self?.updateRequestsBadge()
                    self?.tableView.reloadData()
                }
            }
        }
    }
    
    private func updateRequestsBadge() {
        let pendingCount = pendingRequests.count
        
        if pendingCount > 0 {
            segmentedControl.setTitle("Requests (\(pendingCount))", forSegmentAt: 1)
        } else {
            segmentedControl.setTitle("Requests", forSegmentAt: 1)
        }
    }
    
    // MARK: - Actions
    @objc private func dismissViewController() {
        dismiss(animated: true)
    }
    
    @objc private func clearAllRequestsTapped() {
        let alert = UIAlertController(
            title: "Cleanup Options",
            message: "Choose what to clear",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Clear All Friend Requests", style: .destructive) { [weak self] _ in
            self?.clearAllFriendRequests()
        })
        
        alert.addAction(UIAlertAction(title: "Clear All Friends", style: .destructive) { [weak self] _ in
            self?.clearAllFriends()
        })
        
        alert.addAction(UIAlertAction(title: "Clear Friends for Specific User", style: .destructive) { [weak self] _ in
            self?.clearFriendsForSpecificUser()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func clearAllFriendRequests() {
        let confirmAlert = UIAlertController(
            title: "Clear All Friend Requests",
            message: "This will delete ALL friend requests in the database. Are you sure?",
            preferredStyle: .alert
        )
        
        confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirmAlert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            self?.firebaseService?.clearAllFriendRequests { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.showAlert(title: "Error", message: error.localizedDescription)
                    } else {
                        self?.showAlert(title: "Success", message: "All friend requests cleared!")
                        self?.loadPendingRequests()
                    }
                }
            }
        })
        
        present(confirmAlert, animated: true)
    }
    
    private func clearAllFriends() {
        let confirmAlert = UIAlertController(
            title: "Clear All Friends",
            message: "This will delete ALL friend records in the database. Are you sure?",
            preferredStyle: .alert
        )
        
        confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirmAlert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            self?.firebaseService?.clearAllFriends { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.showAlert(title: "Error", message: error.localizedDescription)
                    } else {
                        self?.showAlert(title: "Success", message: "All friend records cleared!")
                        self?.friends.removeAll()
                        self?.tableView.reloadData()
                    }
                }
            }
        })
        
        present(confirmAlert, animated: true)
    }
    
    private func clearFriendsForSpecificUser() {
        let inputAlert = UIAlertController(
            title: "Clear Friends for User",
            message: "Enter the username",
            preferredStyle: .alert
        )
        
        inputAlert.addTextField { textField in
            textField.placeholder = "Username"
        }
        
        inputAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        inputAlert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let username = inputAlert.textFields?.first?.text, !username.isEmpty else {
                self?.showAlert(title: "Error", message: "Please enter a username")
                return
            }
            
            self?.firebaseService?.clearFriendsForUser(username: username) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.showAlert(title: "Error", message: error.localizedDescription)
                    } else {
                        self?.showAlert(title: "Success", message: "All friend records cleared for \(username)!")
                        self?.loadPendingRequests()
                    }
                }
            }
        })
        
        present(inputAlert, animated: true)
    }
    
    @objc private func segmentChanged() {
        isSearching = segmentedControl.selectedSegmentIndex == 2
        searchBar.isHidden = !isSearching
        searchBar.text = ""
        searchResults.removeAll()
        
        // Refresh data when switching tabs
        if segmentedControl.selectedSegmentIndex == 1 { // Requests tab
            loadPendingRequests()
        }
        
        tableView.reloadData()
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func searchUsers(_ searchText: String) {
        guard !searchText.isEmpty else {
            searchResults.removeAll()
            tableView.reloadData()
            return
        }
        
        firebaseService?.searchUsersByUsername(searchText) { [weak self] users, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Search Error", message: error.localizedDescription)
                } else {
                    self?.searchResults = users
                    // Load friend status for each user
                    self?.loadFriendStatusForSearchResults()
                }
            }
        }
    }
    
    private func loadFriendStatusForSearchResults() {
        guard let firebaseService = firebaseService else { return }
        
        let group = DispatchGroup()
        
        for (index, user) in searchResults.enumerated() {
            group.enter()
            
            // Check if already friends
            firebaseService.checkIfFriends(userId: user.id) { [weak self] isFriend in
                DispatchQueue.main.async {
                    guard let self = self, index < self.searchResults.count else {
                        group.leave()
                        return
                    }
                    
                    if isFriend {
                        self.searchResults[index].friendStatus = .friends
                        group.leave()
                    } else {
                        // Check if there's a pending request
                        firebaseService.checkPendingFriendRequest(toUserId: user.id) { [weak self] hasPendingRequest in
                            DispatchQueue.main.async {
                                guard let self = self, index < self.searchResults.count else {
                                    group.leave()
                                    return
                                }
                                
                                if hasPendingRequest {
                                    self.searchResults[index].friendStatus = .requestSent
                                    group.leave()
                                } else {
                                    // Check if they sent us a request
                                    firebaseService.checkReceivedFriendRequest(fromUserId: user.id) { [weak self] hasReceivedRequest in
                                        DispatchQueue.main.async {
                                            guard let self = self, index < self.searchResults.count else {
                                                group.leave()
                                                return
                                            }
                                            
                                            if hasReceivedRequest {
                                                self.searchResults[index].friendStatus = .requestReceived
                                            } else {
                                                self.searchResults[index].friendStatus = .none
                                            }
                                            group.leave()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.tableView.reloadData()
        }
    }
}

// MARK: - UISearchBarDelegate
extension FriendsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchUsers(searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - SearchResultCellDelegate
extension FriendsViewController: SearchResultCellDelegate {
    func sendFriendRequestTapped(user: UserProfile) {
        firebaseService?.sendFriendRequest(toUsername: user.username) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Error", message: error.localizedDescription)
                } else {
                    self?.showAlert(title: "Success", message: "Friend request sent to \(user.username)")
                    // Refresh search results to update button status
                    if let searchText = self?.searchBar.text, !searchText.isEmpty {
                        self?.searchUsers(searchText)
                    }
                }
            }
        }
    }
    
    func acceptFriendRequestTapped(user: UserProfile) {
        // Find the pending request for this user
        firebaseService?.getPendingFriendRequests { [weak self] requests, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Error", message: error.localizedDescription)
                } else if let request = requests.first(where: { $0.fromUserId == user.id }) {
                    // Accept the friend request
                    self?.firebaseService?.acceptFriendRequest(requestId: request.id) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.showAlert(title: "Error", message: error.localizedDescription)
                            } else {
                                self?.showAlert(title: "Success", message: "You are now friends with \(user.username)")
                                self?.loadPendingRequests()
                                self?.delegate?.friendsDidUpdate()
                                // Refresh search results to update button status
                                if let searchText = self?.searchBar.text, !searchText.isEmpty {
                                    self?.searchUsers(searchText)
                                }
                            }
                        }
                    }
                } else {
                    self?.showAlert(title: "Error", message: "Friend request not found")
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource & Delegate
extension FriendsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearching {
            return searchResults.count
        } else if segmentedControl.selectedSegmentIndex == 0 {
            return friends.count
        } else {
            return pendingRequests.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSearching {
            // Search results
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath) as! SearchResultCell
            let user = searchResults[indexPath.row]
            cell.configure(with: user)
            cell.delegate = self
            return cell
        } else if segmentedControl.selectedSegmentIndex == 0 {
            // Friends
            let cell = tableView.dequeueReusableCell(withIdentifier: "FriendCell", for: indexPath) as! FriendCell
            let friend = friends[indexPath.row]
            cell.configure(with: friend)
            cell.delegate = self
            return cell
        } else {
            // Pending requests
            let cell = tableView.dequeueReusableCell(withIdentifier: "FriendRequestCell", for: indexPath) as! FriendRequestCell
            let request = pendingRequests[indexPath.row]
            cell.configure(with: request)
            cell.delegate = self
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - FriendCellDelegate
extension FriendsViewController: FriendCellDelegate {
    func removeFriendTapped(friend: Friend) {
        let alert = UIAlertController(
            title: "Remove Friend",
            message: "Are you sure you want to remove \(friend.firstName) from your friends?",
            preferredStyle: .alert
        )
        
        let removeAction = UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.firebaseService?.removeFriend(friendId: friend.userId) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.showAlert(title: "Error", message: error.localizedDescription)
                    } else {
                        self?.friends.removeAll { $0.id == friend.id }
                        self?.tableView.reloadData()
                        self?.delegate?.friendsDidUpdate()
                    }
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(removeAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
}

// MARK: - FriendRequestCellDelegate
extension FriendsViewController: FriendRequestCellDelegate {
    func acceptRequestTapped(request: FriendRequest) {
        print("🟢 FriendsVC: Accept button tapped for request \(request.id)")
        print("   From: \(request.fromUsername), To: \(request.toUsername)")
        
        firebaseService?.respondToFriendRequest(requestId: request.id, accept: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ FriendsVC: Accept failed with error: \(error.localizedDescription)")
                    self?.showAlert(title: "Error Accepting Request", message: error.localizedDescription)
                } else {
                    print("✅ FriendsVC: Accept succeeded!")
                    self?.showAlert(title: "Success", message: "You are now friends with \(request.fromUsername)!")
                    self?.pendingRequests.removeAll { $0.id == request.id }
                    self?.updateRequestsBadge()
                    self?.tableView.reloadData()
                    self?.delegate?.friendsDidUpdate()
                }
            }
        }
    }
    
    func declineRequestTapped(request: FriendRequest) {
        print("🔴 FriendsVC: Decline button tapped for request \(request.id)")
        
        firebaseService?.respondToFriendRequest(requestId: request.id, accept: false) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ FriendsVC: Decline failed with error: \(error.localizedDescription)")
                    self?.showAlert(title: "Error", message: error.localizedDescription)
                } else {
                    print("✅ FriendsVC: Decline succeeded!")
                    self?.pendingRequests.removeAll { $0.id == request.id }
                    self?.updateRequestsBadge()
                    self?.tableView.reloadData()
                }
            }
        }
    }
}

// MARK: - FriendCell
class FriendCell: UITableViewCell {
    weak var delegate: FriendCellDelegate?
    private var friend: Friend?
    
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let removeButton = UIButton(type: .system)
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
        
        nameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        nameLabel.textColor = UIColor.white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        usernameLabel.font = UIFont.systemFont(ofSize: 14)
        usernameLabel.textColor = UIColor.gray
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        removeButton.setTitle("Remove", for: .normal)
        removeButton.setTitleColor(.red, for: .normal)
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(containerView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(usernameLabel)
        containerView.addSubview(removeButton)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            usernameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            usernameLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            usernameLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            
            removeButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            removeButton.widthAnchor.constraint(equalToConstant: 80)
        ])
    }
    
    func configure(with friend: Friend) {
        self.friend = friend
        nameLabel.text = friend.firstName
        usernameLabel.text = "@\(friend.username)"
    }
    
    @objc private func removeButtonTapped() {
        guard let friend = friend else { return }
        delegate?.removeFriendTapped(friend: friend)
    }
}

// MARK: - FriendRequestCell
class FriendRequestCell: UITableViewCell {
    weak var delegate: FriendRequestCellDelegate?
    private var request: FriendRequest?
    
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let acceptButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)
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
        
        nameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        nameLabel.textColor = UIColor.white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        usernameLabel.font = UIFont.systemFont(ofSize: 14)
        usernameLabel.textColor = UIColor.gray
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        acceptButton.setTitle("Accept", for: .normal)
        acceptButton.setTitleColor(.green, for: .normal)
        acceptButton.addTarget(self, action: #selector(acceptButtonTapped), for: .touchUpInside)
        acceptButton.translatesAutoresizingMaskIntoConstraints = false
        
        declineButton.setTitle("Decline", for: .normal)
        declineButton.setTitleColor(.red, for: .normal)
        declineButton.addTarget(self, action: #selector(declineButtonTapped), for: .touchUpInside)
        declineButton.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(containerView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(usernameLabel)
        containerView.addSubview(acceptButton)
        containerView.addSubview(declineButton)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: acceptButton.leadingAnchor, constant: -8),
            
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            usernameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            usernameLabel.trailingAnchor.constraint(equalTo: acceptButton.leadingAnchor, constant: -8),
            usernameLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            
            acceptButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            acceptButton.trailingAnchor.constraint(equalTo: declineButton.leadingAnchor, constant: -8),
            acceptButton.widthAnchor.constraint(equalToConstant: 60),
            
            declineButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            declineButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            declineButton.widthAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    func configure(with request: FriendRequest) {
        self.request = request
        nameLabel.text = request.fromUsername
        usernameLabel.text = "@\(request.fromUsername)"
    }
    
    @objc private func acceptButtonTapped() {
        guard let request = request else { return }
        delegate?.acceptRequestTapped(request: request)
    }
    
    @objc private func declineButtonTapped() {
        guard let request = request else { return }
        delegate?.declineRequestTapped(request: request)
    }
}

// MARK: - SearchResultCell
class SearchResultCell: UITableViewCell {
    weak var delegate: SearchResultCellDelegate?
    private var user: UserProfile?
    
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let addButton = UIButton(type: .system)
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
        
        containerView.backgroundColor = UIColor.neonGreen.withAlphaComponent(0.1)
        containerView.layer.cornerRadius = 12
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.neonGreen.withAlphaComponent(0.3).cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        usernameLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        usernameLabel.textColor = UIColor.neonGreen
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        addButton.setTitle("Add", for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.backgroundColor = UIColor.neonGreen
        addButton.layer.cornerRadius = 8
        addButton.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(containerView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(usernameLabel)
        containerView.addSubview(addButton)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -12),
            
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            usernameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            usernameLabel.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -12),
            usernameLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            
            addButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            addButton.widthAnchor.constraint(equalToConstant: 60),
            addButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    func configure(with user: UserProfile) {
        self.user = user
        nameLabel.text = user.firstName
        usernameLabel.text = "@\(user.username)"
        
        // Update button based on friend status
        switch user.friendStatus {
        case .none:
            addButton.setTitle("Add", for: .normal)
            addButton.backgroundColor = UIColor.neonGreen
            addButton.isEnabled = true
        case .friends:
            addButton.setTitle("Friends", for: .normal)
            addButton.backgroundColor = UIColor.gray
            addButton.isEnabled = false
        case .requestSent:
            addButton.setTitle("Request Sent", for: .normal)
            addButton.backgroundColor = UIColor.orange
            addButton.isEnabled = false
        case .requestReceived:
            addButton.setTitle("Accept", for: .normal)
            addButton.backgroundColor = UIColor.blue
            addButton.isEnabled = true
        }
    }
    
    @objc private func addButtonTapped() {
        guard let user = user else { return }
        
        switch user.friendStatus {
        case .none:
            delegate?.sendFriendRequestTapped(user: user)
        case .requestReceived:
            delegate?.acceptFriendRequestTapped(user: user)
        default:
            break
        }
    }
}

// MARK: - Delegate Protocols
protocol FriendCellDelegate: AnyObject {
    func removeFriendTapped(friend: Friend)
}

protocol FriendRequestCellDelegate: AnyObject {
    func acceptRequestTapped(request: FriendRequest)
    func declineRequestTapped(request: FriendRequest)
}

protocol SearchResultCellDelegate: AnyObject {
    func sendFriendRequestTapped(user: UserProfile)
    func acceptFriendRequestTapped(user: UserProfile)
}
