import UIKit

class CommentDisplayView: UIView {
    
    private let tableView = UITableView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let headerView = UIView()
    
    private var comments: [TweetComment] = []
    private var tweetOwnerId: String?
    private var currentUserId: String?
    
    var onClose: (() -> Void)?
    var onDeleteComment: ((String) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = UIColor.systemBackground
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3
        
        // Setup header
        headerView.backgroundColor = UIColor.systemGray6
        headerView.layer.cornerRadius = 16
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        
        titleLabel.text = "Comments"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textAlignment = .center
        
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .systemGray
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        
        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CommentTableViewCell.self, forCellReuseIdentifier: "CommentCell")
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        
        // Add subviews
        addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(closeButton)
        addSubview(tableView)
        
        // Setup constraints
        headerView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),
            
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func configure(with comments: [TweetComment], tweetOwnerId: String, currentUserId: String) {
        self.comments = comments
        self.tweetOwnerId = tweetOwnerId
        self.currentUserId = currentUserId
        tableView.reloadData()
    }
    
    private func canDeleteComment(_ comment: TweetComment) -> Bool {
        guard let currentUserId = currentUserId else { return false }
        // User can delete if they own the comment OR they own the tweet
        return currentUserId == comment.userId || currentUserId == tweetOwnerId
    }
    
    private func handleDeleteComment(at index: Int) {
        guard index < comments.count else { return }
        let comment = comments[index]
        onDeleteComment?(comment.id)
    }
    
    @objc private func closeButtonTapped() {
        onClose?()
    }
}

extension CommentDisplayView: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CommentCell", for: indexPath) as! CommentTableViewCell
        let comment = comments[indexPath.row]
        let canDelete = canDeleteComment(comment)
        
        cell.configure(with: comment, canDelete: canDelete)
        cell.onDelete = { [weak self] in
            self?.handleDeleteComment(at: indexPath.row)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
}

// MARK: - Comment Table View Cell
class CommentTableViewCell: UITableViewCell {
    
    private let usernameLabel = UILabel()
    private let commentLabel = UILabel()
    private let timeLabel = UILabel()
    private let stackView = UIStackView()
    private let deleteButton = UIButton(type: .system)
    
    var onDelete: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Configure stack view
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure labels
        usernameLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        usernameLabel.textColor = .systemBlue
        
        commentLabel.font = UIFont.systemFont(ofSize: 16)
        commentLabel.textColor = .label
        commentLabel.numberOfLines = 0
        
        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.textColor = .secondaryLabel
        
        // Configure delete button
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        deleteButton.isHidden = true  // Hidden by default
        
        // Add subviews
        contentView.addSubview(stackView)
        contentView.addSubview(deleteButton)
        stackView.addArrangedSubview(usernameLabel)
        stackView.addArrangedSubview(commentLabel)
        stackView.addArrangedSubview(timeLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            deleteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            deleteButton.widthAnchor.constraint(equalToConstant: 30),
            deleteButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    func configure(with comment: TweetComment, canDelete: Bool) {
        usernameLabel.text = comment.username
        commentLabel.text = comment.text
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timeLabel.text = formatter.localizedString(for: comment.timestamp, relativeTo: Date())
        
        deleteButton.isHidden = !canDelete
    }
    
    @objc private func deleteButtonTapped() {
        onDelete?()
    }
}
