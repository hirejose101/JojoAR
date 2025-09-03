import UIKit
import SceneKit

class TweetInteractionView: UIView {
    
    // MARK: - UI Components
    private let likeButton = UIButton(type: .system)
    private let commentButton = UIButton(type: .system)
    private let likeCountLabel = UILabel()
    private let commentCountLabel = UILabel()
    private let stackView = UIStackView()
    
    // MARK: - Properties
    var tweetId: String?
    var onLikeTapped: ((String) -> Void)?
    var onCommentTapped: ((String) -> Void)?
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 8
        layer.masksToBounds = true
        
        // Configure stack view
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure like button
        likeButton.setImage(UIImage(systemName: "heart"), for: .normal)
        likeButton.setImage(UIImage(systemName: "heart.fill"), for: .selected)
        likeButton.tintColor = .white
        likeButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        likeButton.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        
        // Configure comment button
        commentButton.setImage(UIImage(systemName: "bubble.left"), for: .normal)
        commentButton.tintColor = .white
        commentButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        commentButton.addTarget(self, action: #selector(commentButtonTapped), for: .touchUpInside)
        
        // Configure labels
        likeCountLabel.textColor = .white
        likeCountLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        likeCountLabel.textAlignment = .center
        
        commentCountLabel.textColor = .white
        commentCountLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        commentCountLabel.textAlignment = .center
        
        // Add subviews
        addSubview(stackView)
        
        // Add buttons to stack view
        stackView.addArrangedSubview(likeButton)
        stackView.addArrangedSubview(commentButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            
            likeButton.heightAnchor.constraint(equalToConstant: 24),
            commentButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    // MARK: - Public Methods
    func configure(with tweet: PersistentTweet, isLiked: Bool = false) {
        tweetId = tweet.id
        
        // Update like button
        likeButton.isSelected = isLiked
        likeButton.tintColor = isLiked ? .systemRed : .white
        
        // Update counts
        likeCountLabel.text = tweet.likeCount > 0 ? "\(tweet.likeCount)" : ""
        commentCountLabel.text = tweet.commentCount > 0 ? "\(tweet.commentCount)" : ""
        
        // Update button titles
        likeButton.setTitle(tweet.likeCount > 0 ? " \(tweet.likeCount)" : "", for: .normal)
        commentButton.setTitle(tweet.commentCount > 0 ? " \(tweet.commentCount)" : "", for: .normal)
    }
    
    func updateLikeState(isLiked: Bool, likeCount: Int) {
        likeButton.isSelected = isLiked
        likeButton.tintColor = isLiked ? .systemRed : .white
        likeButton.setTitle(likeCount > 0 ? " \(likeCount)" : "", for: .normal)
    }
    
    func updateCommentCount(_ count: Int) {
        commentButton.setTitle(count > 0 ? " \(count)" : "", for: .normal)
    }
    
    // MARK: - Actions
    @objc private func likeButtonTapped() {
        guard let tweetId = tweetId else { return }
        onLikeTapped?(tweetId)
    }
    
    @objc private func commentButtonTapped() {
        guard let tweetId = tweetId else { return }
        onCommentTapped?(tweetId)
    }
}

// MARK: - Comment Input View
class CommentInputView: UIView {
    
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let stackView = UIStackView()
    
    var onSendComment: ((String) -> Void)?
    
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
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.3
        
        // Configure stack view
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure text field
        textField.placeholder = "Add a comment..."
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.returnKeyType = .send
        textField.delegate = self
        
        // Configure send button
        sendButton.setTitle("Send", for: .normal)
        sendButton.setTitleColor(.systemBlue, for: .normal)
        sendButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        
        // Add subviews
        addSubview(stackView)
        stackView.addArrangedSubview(textField)
        stackView.addArrangedSubview(sendButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            
            sendButton.widthAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    @objc private func sendButtonTapped() {
        sendComment()
    }
    
    private func sendComment() {
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        
        onSendComment?(text)
        textField.text = ""
        textField.resignFirstResponder()
    }
}

extension CommentInputView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendComment()
        return true
    }
}
