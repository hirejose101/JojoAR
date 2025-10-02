import UIKit

class FriendsViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: FriendsViewControllerDelegate?
    var friends: [Friend] = []
    var pendingRequests: [FriendRequest] = []
    private var firebaseService: FirebaseService?
    
    // MARK: - UI Elements
    private let segmentedControl = UISegmentedControl(items: ["Friends", "Requests"])
    private let tableView = UITableView()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFirebase()
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
        
        // Segmented control
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.backgroundColor = UIColor.neonGreen.withAlphaComponent(0.3)
        segmentedControl.selectedSegmentTintColor = UIColor.neonGreen
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        
        // Table view
        tableView.backgroundColor = UIColor.black
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(FriendCell.self, forCellReuseIdentifier: "FriendCell")
        tableView.register(FriendRequestCell.self, forCellReuseIdentifier: "FriendRequestCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupFirebase() {
        firebaseService = FirebaseService()
    }
    
    // MARK: - Actions
    @objc private func dismissViewController() {
        dismiss(animated: true)
    }
    
    @objc private func segmentChanged() {
        tableView.reloadData()
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate
extension FriendsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return segmentedControl.selectedSegmentIndex == 0 ? friends.count : pendingRequests.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if segmentedControl.selectedSegmentIndex == 0 {
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
        firebaseService?.respondToFriendRequest(requestId: request.id, accept: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Error", message: error.localizedDescription)
                } else {
                    self?.pendingRequests.removeAll { $0.id == request.id }
                    self?.tableView.reloadData()
                    self?.delegate?.friendsDidUpdate()
                }
            }
        }
    }
    
    func declineRequestTapped(request: FriendRequest) {
        firebaseService?.respondToFriendRequest(requestId: request.id, accept: false) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Error", message: error.localizedDescription)
                } else {
                    self?.pendingRequests.removeAll { $0.id == request.id }
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

// MARK: - Delegate Protocols
protocol FriendCellDelegate: AnyObject {
    func removeFriendTapped(friend: Friend)
}

protocol FriendRequestCellDelegate: AnyObject {
    func acceptRequestTapped(request: FriendRequest)
    func declineRequestTapped(request: FriendRequest)
}
