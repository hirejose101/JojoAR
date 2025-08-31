import UIKit
import Firebase
import FirebaseAuth

class RegistrationViewController: UIViewController {
    
    // MARK: - UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Create Account"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Join the AR community and start sharing your world!"
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let firstNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "First Name"
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let usernameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Username"
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let dateOfBirthTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Date of Birth"
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Email"
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.keyboardType = .emailAddress
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let passwordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Password"
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Confirm Password"
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let createAccountButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create Account", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(UIColor.white, for: .normal)
        button.layer.cornerRadius = 25
        button.layer.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let signInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Already have an account? Sign In", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        button.setTitleColor(UIColor.systemBlue, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(activityIndicatorStyle: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Properties
    private let datePicker = UIDatePicker()
    private let firebaseService = FirebaseService()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupDatePicker()
        setupActions()
        
        // Add navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.title = "Create Account"
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(firstNameTextField)
        contentView.addSubview(usernameTextField)
        contentView.addSubview(dateOfBirthTextField)
        contentView.addSubview(emailTextField)
        contentView.addSubview(passwordTextField)
        contentView.addSubview(confirmPasswordTextField)
        contentView.addSubview(createAccountButton)
        contentView.addSubview(signInButton)
        contentView.addSubview(activityIndicator)
        
        // Add text field delegates
        firstNameTextField.delegate = self
        usernameTextField.delegate = self
        dateOfBirthTextField.delegate = self
        emailTextField.delegate = self
        passwordTextField.delegate = self
        confirmPasswordTextField.delegate = self
    }
    
    private func setupConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // First Name
            firstNameTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 30),
            firstNameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            firstNameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            firstNameTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Username
            usernameTextField.topAnchor.constraint(equalTo: firstNameTextField.bottomAnchor, constant: 16),
            usernameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            usernameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            usernameTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Date of Birth
            dateOfBirthTextField.topAnchor.constraint(equalTo: usernameTextField.bottomAnchor, constant: 16),
            dateOfBirthTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            dateOfBirthTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            dateOfBirthTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Email
            emailTextField.topAnchor.constraint(equalTo: dateOfBirthTextField.bottomAnchor, constant: 16),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            emailTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Password
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Confirm Password
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 16),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Create Account Button
            createAccountButton.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: 30),
            createAccountButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            createAccountButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            createAccountButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Sign In Button
            signInButton.topAnchor.constraint(equalTo: createAccountButton.bottomAnchor, constant: 20),
            signInButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 20),
            activityIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupDatePicker() {
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.maximumDate = Date()
        
        // Set default date to 18 years ago
        let calendar = Calendar.current
        let eighteenYearsAgo = calendar.date(byAdding: .year, value: -18, to: Date()) ?? Date()
        datePicker.setDate(eighteenYearsAgo, animated: false)
        
        dateOfBirthTextField.inputView = datePicker
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(datePickerDone))
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(datePickerCancel))
        
        toolbar.setItems([cancelButton, flexSpace, doneButton], animated: false)
        dateOfBirthTextField.inputAccessoryView = toolbar
    }
    
    private func setupActions() {
        createAccountButton.addTarget(self, action: #selector(createAccountTapped), for: .touchUpInside)
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
    }
    
    // MARK: - Actions
    @objc private func createAccountTapped() {
        guard validateInputs() else { return }
        
        let firstName = firstNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = usernameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordTextField.text ?? ""
        let dateOfBirth = datePicker.date
        
        // Show loading state
        setLoadingState(true)
        
        firebaseService.createUserAccount(
            email: email,
            password: password,
            firstName: firstName,
            username: username,
            dateOfBirth: dateOfBirth
        ) { [weak self] user, error in
            DispatchQueue.main.async {
                self?.setLoadingState(false)
                
                if let error = error {
                    self?.showError(error.localizedDescription)
                } else {
                    self?.showSuccess()
                }
            }
        }
    }
    
    @objc private func signInTapped() {
        // Navigate to sign in view controller
        let signInVC = SignInViewController()
        let navController = UINavigationController(rootViewController: signInVC)
        present(navController, animated: true)
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func datePickerDone() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        dateOfBirthTextField.text = formatter.string(from: datePicker.date)
        dateOfBirthTextField.resignFirstResponder()
    }
    
    @objc private func datePickerCancel() {
        dateOfBirthTextField.resignFirstResponder()
    }
    
    // MARK: - Helper Methods
    private func validateInputs() -> Bool {
        let firstName = firstNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = usernameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordTextField.text ?? ""
        let confirmPassword = confirmPasswordTextField.text ?? ""
        
        // Check if fields are empty
        if firstName.isEmpty {
            showError("Please enter your first name")
            return false
        }
        
        if username.isEmpty {
            showError("Please enter a username")
            return false
        }
        
        if username.count < 3 {
            showError("Username must be at least 3 characters long")
            return false
        }
        
        if dateOfBirthTextField.text?.isEmpty ?? true {
            showError("Please select your date of birth")
            return false
        }
        
        if email.isEmpty {
            showError("Please enter your email")
            return false
        }
        
        if !isValidEmail(email) {
            showError("Please enter a valid email address")
            return false
        }
        
        if password.isEmpty {
            showError("Please enter a password")
            return false
        }
        
        if password.count < 6 {
            showError("Password must be at least 6 characters long")
            return false
        }
        
        if password != confirmPassword {
            showError("Passwords do not match")
            return false
        }
        
        return true
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func setLoadingState(_ isLoading: Bool) {
        if isLoading {
            activityIndicator.startAnimating()
            createAccountButton.isEnabled = false
            createAccountButton.alpha = 0.6
        } else {
            activityIndicator.stopAnimating()
            createAccountButton.isEnabled = true
            createAccountButton.alpha = 1.0
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showSuccess() {
        let alert = UIAlertController(title: "Success!", message: "Your account has been created successfully!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            // Post notification to inform main view controller about auth state change
            NotificationCenter.default.post(name: NSNotification.Name("AuthenticationStateChanged"), object: nil)
            
            // Dismiss the registration view controller
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate
extension RegistrationViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case firstNameTextField:
            usernameTextField.becomeFirstResponder()
        case usernameTextField:
            dateOfBirthTextField.becomeFirstResponder()
        case dateOfBirthTextField:
            emailTextField.becomeFirstResponder()
        case emailTextField:
            passwordTextField.becomeFirstResponder()
        case passwordTextField:
            confirmPasswordTextField.becomeFirstResponder()
        case confirmPasswordTextField:
            textField.resignFirstResponder()
            createAccountTapped()
        default:
            textField.resignFirstResponder()
        }
        return true
    }
}
