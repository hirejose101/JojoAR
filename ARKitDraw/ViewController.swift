//
//  ViewController.swift
//  ARKitDraw
//
//  Created by Felix Lapalme on 2017-06-07.
//  Copyright © 2017 Felix Lapalme. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreLocation
import MapKit
import FirebaseAuth

// MARK: - Street Sign Style Text System
/// Creates street sign-style AR text nodes with proper centering and no drift
func makeStreetSignNode(
    text: String,
    primaryFontName: String? = "AvenirNext-Heavy",
    fallbackWeight: UIFont.Weight = .heavy,
    targetTextHeightMeters: CGFloat = 0.08,   // final text height in AR (tweak)
    horizontalPaddingMeters: CGFloat = 0.04,  // board padding left/right
    verticalPaddingMeters: CGFloat = 0.024,   // board padding top/bottom
    textColor: UIColor = .white,
    boardColor: UIColor = .black,
    cornerRadiusMeters: CGFloat = 0.01,       // rounded board corners
    billboard: Bool = true                    // always face camera
) -> SCNNode {

    // 1) Build the SCNText (no extrusion for a flat sign)
    let uiFont: UIFont = {
        if let n = primaryFontName, let f = UIFont(name: n, size: 220) {
            return f
        }
        return UIFont.systemFont(ofSize: 220, weight: fallbackWeight)
    }()

    let scnText = SCNText(string: text, extrusionDepth: 0.0)
    scnText.font = uiFont
    scnText.flatness = 0.006  // smoother curves
    scnText.chamferRadius = 0 // not needed for flat

    // Materials: unlit so room lighting doesn't wash out the sign
    let face = SCNMaterial()
    face.diffuse.contents = textColor
    face.lightingModel = .constant
    face.isDoubleSided = false
    scnText.firstMaterial = face

    let textNode = SCNNode(geometry: scnText)

    // 2) Normalize size: scale the text so its *height* matches targetTextHeightMeters
    // Measure bounds (in its native size)
    scnText.string = text // ensure layout
    let boundingBox = scnText.boundingBox
    let nativeWidth  = CGFloat(boundingBox.max.x - boundingBox.min.x)
    let nativeHeight = CGFloat(boundingBox.max.y - boundingBox.min.y)
    let scale = targetTextHeightMeters / max(nativeHeight, 0.0001)
    textNode.scale = SCNVector3(scale, scale, scale)

    // 3) Center the text around its origin (so it aligns with board center)
    let centeredPivot = SCNMatrix4MakeTranslation(
        (boundingBox.min.x + boundingBox.max.x) * 0.5,
        (boundingBox.min.y + boundingBox.max.y) * 0.5,
        (boundingBox.min.z + boundingBox.max.z) * 0.5
    )
    textNode.pivot = centeredPivot

    // Recompute the text size after scaling
    let textWidthMeters  = nativeWidth  * scale
    let textHeightMeters = nativeHeight * scale

    // 4) Build the board (SCNPlane) with padding
    let boardWidth  = textWidthMeters  + 2 * horizontalPaddingMeters
    let boardHeight = textHeightMeters + 2 * verticalPaddingMeters

    let boardPlane = SCNPlane(width: boardWidth, height: boardHeight)
    let boardMat = SCNMaterial()
    boardMat.diffuse.contents = boardColor
    boardMat.lightingModel = .constant
    boardMat.isDoubleSided = true
    boardPlane.cornerRadius = cornerRadiusMeters
    boardPlane.firstMaterial = boardMat

    let boardNode = SCNNode(geometry: boardPlane)

    // 5) Center board as well (plane's origin is already centered, so pivot OK by default)
    // Slight Z offset for text to sit "above" board, preventing z-fighting
    textNode.position = SCNVector3(0, 0, 0.001)

    // 6) Group both under a single parent (the street sign)
    let signNode = SCNNode()
    signNode.castsShadow = false
    signNode.addChildNode(boardNode)
    signNode.addChildNode(textNode)

    if billboard {
        signNode.constraints = [SCNBillboardConstraint()] // always face camera
    }

    return signNode
}

// MARK: - GTA Style Text System
/// Professional GTA-style 3D text with proper stroke and performance optimization
class GTAText {
    
    // MARK: - Shared materials (reuse for perf)
    enum Style {
        static let whiteFace: SCNMaterial = {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = UIColor.white
            m.metalness.contents = 0.0
            m.roughness.contents = 0.5
            m.isDoubleSided = false
            return m
        }()
        static let blackSide: SCNMaterial = {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = UIColor.black
            m.metalness.contents = 0.0
            m.roughness.contents = 0.6
            m.isDoubleSided = false
            return m
        }()
        static let blackStroke: SCNMaterial = {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.black
            m.emission.contents = UIColor.black
            m.isDoubleSided = true
            // Stroke shouldn't write depth (prevents shimmer with main text)
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            return m
        }()
    }
    
    // MARK: - Geometry cache
    final class TextGeoCache {
        static var cache: [String: SCNText] = [:]
        static func geometry(
            _ text: String,
            font: UIFont,
            extrusion: CGFloat,
            chamfer: CGFloat,
            flatness: CGFloat
        ) -> SCNText {
            let key = "\(text)|\(font.fontName)|\(extrusion)|\(chamfer)|\(flatness)"
            if let g = cache[key] { return g.copy() as! SCNText }
            let g = SCNText(string: text, extrusionDepth: extrusion)
            g.font = font
            g.chamferRadius = chamfer
            g.flatness = flatness
            cache[key] = g
            return g.copy() as! SCNText
        }
    }
    
    // MARK: - GTA 3D text node (white face + black stroke)
    static func createGTATextNode(
        text: String,
        font: UIFont = UIFont(name: "AvenirNext-Heavy", size: 0.22) ?? .systemFont(ofSize: 0.22, weight: .heavy),
        extrusion: CGFloat = 0.06,      // chunky
        chamfer: CGFloat = 0.004,       // rounded edge
        flatness: CGFloat = 0.015,      // smooth curves
        strokeScale: CGFloat = 1.14,    // stroke thickness
        billboard: Bool = true
    ) -> SCNNode {

        // Main 3D white text
        let mainGeo = TextGeoCache.geometry(text, font: font, extrusion: extrusion, chamfer: chamfer, flatness: flatness)
        mainGeo.materials = [Style.whiteFace, Style.blackSide] // element 0: faces, 1: sides (usual order)

        let mainNode = SCNNode(geometry: mainGeo)
        centerPivot(mainNode)

        // Black stroke clone (scaled up)
        let strokeGeo = mainGeo.copy() as! SCNText
        strokeGeo.materials = [Style.blackStroke]
        let strokeNode = SCNNode(geometry: strokeGeo)
        strokeNode.pivot = mainNode.pivot
        strokeNode.scale = SCNVector3(strokeScale, strokeScale, 1.0)
        strokeNode.position.z = -0.001    // sit just behind
        strokeNode.renderingOrder = 5

        // Main in front, writes depth
        mainNode.renderingOrder = 10
        mainNode.geometry?.firstMaterial?.readsFromDepthBuffer = true
        mainNode.geometry?.firstMaterial?.writesToDepthBuffer = true

        // Container (billboarded)
        let container = SCNNode()
        container.addChildNode(strokeNode)
        container.addChildNode(mainNode)
        if billboard { container.constraints = [SCNBillboardConstraint()] }

        return container
    }
    
    // Helper: center pivot so transforms are around the center
    private static func centerPivot(_ node: SCNNode) {
        let (minV, maxV) = node.boundingBox
        let c = SCNVector3((minV.x+maxV.x)/2, (minV.y+maxV.y)/2, (minV.z+maxV.z)/2)
        node.pivot = SCNMatrix4MakeTranslation(c.x, c.y, c.z)
    }
    /// Creates a thought bubble with neon text inside a rounded bar
    static func makeThoughtBarNode(text: String) -> SCNNode {
        let container = SCNNode()

        // --- TEXT (use your GTA-style helper) ---
        let textNode = GTAText.createGTATextNode(
            text: text,
            font: UIFont.systemFont(ofSize: 0.22, weight: .heavy),
            extrusion: 0.06,                               // Chunky GTA depth
            chamfer: 0.004,                                // Rounded edges
            flatness: 0.015,                               // Smooth curves
            strokeScale: 1.14,                             // Perfect black stroke thickness
            billboard: false                               // IMPORTANT: billboard only on container
        )

        // Get text size in local space
        let (tmin, tmax) = (textNode.geometry as! SCNText).boundingBox
        let tW = CGFloat(tmax.x - tmin.x)
        let tH = CGFloat(tmax.y - tmin.y)

        // --- BAR (rounded pill via SpriteKit texture) ---
        // Pad around the text
        let padX: CGFloat = max(0.06, tW * 0.25)
        let padY: CGFloat = max(0.03, tH * 0.6)
        let barW = tW + padX
        let barH = max(tH + padY, 0.06)

        let barPlane = SCNPlane(width: barW, height: barH)
        let sk = SKScene(size: CGSize(width: 800, height: Int(800 * (barH/barW))))
        sk.backgroundColor = UIColor.clear
        let rect = CGRect(x: 40, y: 40, width: sk.size.width - 80, height: sk.size.height - 80)
        let pill = SKShapeNode(rect: rect, cornerRadius: rect.height/2)
        pill.fillColor = UIColor.white
        pill.strokeColor = UIColor.clear
        pill.alpha = 0.85
        pill.setScale(1.0)
        sk.addChild(pill)

        let barMat = SCNMaterial()
        barMat.lightingModel = .constant
        barMat.diffuse.contents = sk
        barMat.isDoubleSided = true
        barPlane.materials = [barMat]

        let barNode = SCNNode(geometry: barPlane)

        // --- ALIGN PIVOTS & POSITIONS ---
        // Center pivots for both so (0,0,0) is their center
        func centerPivot(_ node: SCNNode) {
            let (minV, maxV) = node.boundingBox
            let c = SCNVector3((minV.x+maxV.x)/2, (minV.y+maxV.y)/2, (minV.z+maxV.z)/2)
            node.pivot = SCNMatrix4MakeTranslation(c.x, c.y, c.z)
        }
        centerPivot(textNode)
        centerPivot(barNode)

        // Stack them: text slightly in front to avoid z-fighting
        barNode.position = SCNVector3(0, 0, 0)
        textNode.position = SCNVector3(0, 0, 0.001)

        // Add to container and billboard the container
        container.addChildNode(barNode)
        container.addChildNode(textNode)
        container.constraints = [SCNBillboardConstraint()]

        // Optional: set a consistent scale; tweak as needed
        container.scale = SCNVector3(1, 1, 1)
        return container
    }
}

class ViewController: UIViewController, ARSCNViewDelegate, UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource, MiniMapSearchDelegate {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var textField: UITextField!
    
    // Array to track all tweet nodes and their text
    private var tweetNodes: [SCNNode] = []
    private var tweetTexts: [String] = []
    
    // UI elements for tweet history
    private var historyButton: UIButton!
    private var historyTableView: UITableView!
    private var isHistoryVisible = false
    
    // Color picker elements
    private var colorPickerButton: UIButton!
    private var colorPickerView: UIView!
    private var selectedBorderColor: UIColor {
        get {
            // Load saved color from UserDefaults, default to black
            if let colorData = UserDefaults.standard.data(forKey: "selectedBorderColor") {
                do {
                    if let color = try NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
                        return color
                    }
                } catch {
                    print("⚠️ Failed to load border color: \(error)")
                }
            }
            return UIColor.black
        }
        set {
            // Save color to UserDefaults
            do {
                let colorData = try NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false)
                UserDefaults.standard.set(colorData, forKey: "selectedBorderColor")
            } catch {
                print("⚠️ Failed to save border color: \(error)")
            }
        }
    }
    private var isColorPickerVisible = false
    
    // Tap to place functionality
    private var pendingTweetText: String?
    private var isWaitingForTap = false
    
    // Firebase and Location services
    private var firebaseService: FirebaseService!
    private var locationManager: LocationManager!
    private var nearbyTweets: [PersistentTweet] = []
    private var currentUserId: String?
    
    // Mini-map
    private var miniMapView: MiniMapView!
    
    // Add these properties to prevent duplicate tweet rendering
    private var renderedNearbyTweetIds: Set<String> = []
    private var lastNearbyTweetsUpdate: Date?
    private let nearbyTweetsUpdateCooldown: TimeInterval = 3.0 // 3 seconds cooldown
    
    // Guidance UI for ARKit tracking stability
    private var guidanceLabel: UILabel!
    
    // See Tweets button and notification tracking
    private var seeTweetsButton: UIButton!
    private var notifiedTweetIds: Set<String> = []
    
    // Authentication UI - now integrated into history table
    private var isUserAuthenticated: Bool = false
    private var userInfoLabel: UILabel!
    
    // UI setup flag
    private var hasSetupUI = false
    
    // Prevent duplicate user tweet loading
    private var isLoadingUserTweets = false
    
    // MARK: - Like and Comment Functionality
    private var tweetInteractionViews: [String: TweetInteractionView] = [:]
    private var commentInputView: CommentInputView?
    private var commentInputViewBottomConstraint: NSLayoutConstraint?
    private var commentDisplayView: CommentDisplayView?
    private var selectedTweetId: String?
    private var currentUserProfile: UserProfile?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Set text field delegate
        textField.delegate = self
        
        // Hide statistics for cleaner interface
        sceneView.showsStatistics = false
        
        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/world.scn")!
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Configure modern lighting for neon effects
        configureModernLighting(for: scene)
        
        // Initialize Firebase and Location services
        setupServices()
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        // Add notification observer for authentication state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthenticationStateChanged),
            name: NSNotification.Name("AuthenticationStateChanged"),
            object: nil
        )
        
        // Add keyboard notification observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: NSNotification.Name.UIKeyboardWillShow,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: NSNotification.Name.UIKeyboardWillHide,
            object: nil
        )
        
        // Refresh all existing tweets with new iMessage design after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshAllExistingTweets()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Run the view's session
        sceneView.session.run(configuration)
        
        // Update authentication UI when returning from other screens
        // Only update if services are initialized
        if firebaseService != nil {
            updateAuthenticationUI()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
        
        // Stop location updates
        locationManager?.stopLocationUpdates()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Setup UI after IBOutlets are guaranteed to be connected
        if !hasSetupUI && textField != nil && button != nil {
            setupUI()
            hasSetupUI = true
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    func setupUI() {
        // Safety check - ensure IBOutlets are connected
        guard let textField = textField,
              let button = button else {
            print("Warning: IBOutlets not yet connected, skipping UI setup")
            return
        }
        
        // Configure text field
        textField.placeholder = "What's your thought here?"
        textField.borderStyle = .none
        textField.backgroundColor = UIColor.white
        textField.textColor = UIColor.black
        textField.layer.cornerRadius = 12
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemGray4.cgColor
        textField.font = getCustomFont(size: 16)
        textField.attributedPlaceholder = NSAttributedString(
            string: "What's your thought here?",
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.systemGray]
        )
        
        // Add padding to prevent text from touching borders
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: textField.frame.height))
        textField.leftView = paddingView
        textField.leftViewMode = .always
        
        // Configure button
        button.setTitle("Enter", for: .normal)
        button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        button.setTitleColor(UIColor.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.systemGreen.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 8
        button.layer.shadowOpacity = 0.6
        button.titleLabel?.font = getCustomFont(size: 18)
        
        // Add button action
        button.addTarget(self, action: #selector(enterButtonTapped), for: .touchUpInside)
        
        // Add color picker button (smaller size for text field)
        colorPickerButton = UIButton(type: .system)
        colorPickerButton.setTitle("🎨", for: .normal)
        colorPickerButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        colorPickerButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        colorPickerButton.setTitleColor(UIColor.white, for: .normal)
        colorPickerButton.layer.cornerRadius = 15
        colorPickerButton.layer.masksToBounds = true
        colorPickerButton.layer.borderWidth = 1
        colorPickerButton.layer.borderColor = UIColor.white.cgColor
        colorPickerButton.addTarget(self, action: #selector(colorPickerButtonTapped), for: .touchUpInside)
        
        // Set color picker button as right view of text field with padding
        let rightViewContainer = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 40))
        rightViewContainer.addSubview(colorPickerButton)
        
        // Position button with right padding (stays on right end)
        colorPickerButton.frame = CGRect(x: 20, y: 5, width: 30, height: 30)
        
        textField.rightView = rightViewContainer
        textField.rightViewMode = .always
        
        // Add tweet history button
        historyButton = UIButton(type: .system)
        historyButton.setImage(UIImage(systemName: "person.fill"), for: .normal)
        historyButton.tintColor = UIColor.white
        historyButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        historyButton.layer.cornerRadius = 25
        historyButton.layer.masksToBounds = true
        historyButton.layer.borderWidth = 2
        historyButton.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.8).cgColor
        historyButton.layer.shadowColor = UIColor.systemGreen.cgColor
        historyButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        historyButton.layer.shadowRadius = 8
        historyButton.layer.shadowOpacity = 0.6
        historyButton.translatesAutoresizingMaskIntoConstraints = false
        historyButton.addTarget(self, action: #selector(historyButtonTapped), for: .touchUpInside)
        
        // Configure icon size and appearance
        historyButton.imageView?.contentMode = .scaleAspectFit
        historyButton.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        view.addSubview(historyButton)
        
        // Position history button aligned with text field
        NSLayoutConstraint.activate([
            historyButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            historyButton.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            historyButton.widthAnchor.constraint(equalToConstant: 50),
            historyButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        

        
        // Add history table view (initially hidden)
        historyTableView = UITableView()
        historyTableView.backgroundColor = UIColor.black.withAlphaComponent(0.95)
        historyTableView.layer.cornerRadius = 15
        historyTableView.layer.masksToBounds = true
        historyTableView.layer.borderWidth = 2
        historyTableView.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.6).cgColor
        historyTableView.separatorStyle = .none
        historyTableView.delegate = self
        historyTableView.dataSource = self
        historyTableView.register(UITableViewCell.self, forCellReuseIdentifier: "TweetCell")
        
        historyTableView.translatesAutoresizingMaskIntoConstraints = false
        historyTableView.isHidden = true
        view.addSubview(historyTableView)
        
        // Position history table view below the button
        NSLayoutConstraint.activate([
            historyTableView.topAnchor.constraint(equalTo: historyButton.bottomAnchor, constant: 5),
            historyTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            historyTableView.widthAnchor.constraint(equalToConstant: 250),
            historyTableView.heightAnchor.constraint(equalToConstant: 200)
        ])
        
        // Setup mini-map
        setupMiniMap()
        
        // Setup guidance UI
        setupGuidanceUI()
        
        // Setup See Tweets button
        setupSeeTweetsButton()
        
        // Setup authentication UI after all UI elements are created
        setupAuthenticationUI()
        
        // Setup like and comment interaction views
        setupInteractionViews()
    }
    
    func setupMiniMap() {
        // Create mini-map view
        miniMapView = MiniMapView(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        miniMapView.translatesAutoresizingMaskIntoConstraints = false
        miniMapView.setSearchDelegate(self)
        view.addSubview(miniMapView)
        
        // Position mini-map at bottom-right corner
        NSLayoutConstraint.activate([
            miniMapView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            miniMapView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            miniMapView.widthAnchor.constraint(equalToConstant: 160),
            miniMapView.heightAnchor.constraint(equalToConstant: 160)
        ])
    }
    
    func setupInteractionViews() {
        // Initialize comment input view
        commentInputView = CommentInputView()
        commentInputView?.translatesAutoresizingMaskIntoConstraints = false
        commentInputView?.isHidden = true
        
        if let commentInputView = commentInputView {
            view.addSubview(commentInputView)
            
            // Store the bottom constraint so we can modify it when keyboard appears
            commentInputViewBottomConstraint = commentInputView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            
            NSLayoutConstraint.activate([
                commentInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                commentInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                commentInputViewBottomConstraint!,
                commentInputView.heightAnchor.constraint(equalToConstant: 60)
            ])
        }
        
        // Initialize comment display view
        commentDisplayView = CommentDisplayView()
        commentDisplayView?.translatesAutoresizingMaskIntoConstraints = false
        commentDisplayView?.isHidden = true
        
        if let commentDisplayView = commentDisplayView {
            view.addSubview(commentDisplayView)
            
            NSLayoutConstraint.activate([
                commentDisplayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                commentDisplayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                commentDisplayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
                commentDisplayView.heightAnchor.constraint(equalToConstant: 300)
            ])
            
            commentDisplayView.onClose = { [weak self] in
                self?.hideCommentDisplay()
            }
        }
    }
    
    func setupGuidanceUI() {
        // Create guidance label
        guidanceLabel = UILabel()
        guidanceLabel.textAlignment = .center
        guidanceLabel.textColor = .white
        guidanceLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        guidanceLabel.layer.cornerRadius = 10
        guidanceLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        guidanceLabel.numberOfLines = 0
        guidanceLabel.isHidden = true
        guidanceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(guidanceLabel)
        
        // Position in middle center of screen
        NSLayoutConstraint.activate([
            guidanceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guidanceLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            guidanceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            guidanceLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            guidanceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }
    
    func setupSeeTweetsButton() {
        // Create See Tweets button
        seeTweetsButton = UIButton(type: .system)
        seeTweetsButton.setTitle("See Tweets", for: .normal)
        seeTweetsButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        seeTweetsButton.setTitleColor(.white, for: .normal)
        seeTweetsButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        seeTweetsButton.layer.cornerRadius = 12
        seeTweetsButton.layer.shadowColor = UIColor.black.cgColor
        seeTweetsButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        seeTweetsButton.layer.shadowOpacity = 0.3
        seeTweetsButton.layer.shadowRadius = 4
        seeTweetsButton.isHidden = false // Always visible
        seeTweetsButton.addTarget(self, action: #selector(seeTweetsButtonTapped), for: .touchUpInside)
        seeTweetsButton.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(seeTweetsButton)
        
        // Position in bottom center
        NSLayoutConstraint.activate([
            seeTweetsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            seeTweetsButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            seeTweetsButton.widthAnchor.constraint(equalToConstant: 150),
            seeTweetsButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    func showTweetsDiscoveredNotification(count: Int) {
        let message = count == 1 ? "New tweet detected, Click 'See Tweets' button to view it" : "New tweets detected, Click 'See Tweets' button to view them"
        guidanceLabel.text = message
        guidanceLabel.textColor = .blue
        guidanceLabel.isHidden = false
        
        // Hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.guidanceLabel.isHidden = true
        }
    }
    
    func showStabilityGuidance() {
        guidanceLabel.text = "Hold phone steady for a few secs"
        guidanceLabel.textColor = .orange
        guidanceLabel.isHidden = false
        
        // Hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.guidanceLabel.isHidden = true
        }
    }
    
    @objc func seeTweetsButtonTapped() {
        // Show stability guidance
        showStabilityGuidance()
        
        // Render tweets after a delay to let user hold steady
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.renderNearbyTweetsInAR()
        }
    }
    
    func renderNearbyTweetsInAR() {
        print("🔘 See Tweets button tapped - starting AR rendering")
        
        // Get current nearby tweets and render them
        let currentLocation = locationManager.currentLocation
        guard let currentLoc = currentLocation else { 
            print("❌ No current location available")
            return 
        }
        
        print("📍 Current location: \(currentLoc.coordinate.latitude), \(currentLoc.coordinate.longitude)")
        print("📊 Total nearby tweets: \(nearbyTweets.count)")
        print("📊 Already rendered tweets: \(renderedNearbyTweetIds.count)")
        
        // Get all tweets within 20m that haven't been rendered yet
        let tweetsToRender = nearbyTweets.filter { tweet in
            !renderedNearbyTweetIds.contains(tweet.id)
        }
        
        print("🎯 Tweets to render: \(tweetsToRender.count)")
        
        // Render each tweet
        for tweet in tweetsToRender {
            let tweetLocation = CLLocation(latitude: tweet.latitude, longitude: tweet.longitude)
            let distance = currentLoc.distance(from: tweetLocation)
            
            print("📱 Rendering tweet: '\(tweet.text)' at distance: \(Int(distance))m")
            
            let textNode = createTextNode(text: tweet.text, position: tweet.worldPosition, distance: distance)
            textNode.name = "nearby_tweet_\(tweet.id)"
            
            sceneView.scene.rootNode.addChildNode(textNode)
            renderedNearbyTweetIds.insert(tweet.id)
        }
        
        if !tweetsToRender.isEmpty {
            print("✨ Successfully rendered \(tweetsToRender.count) tweets in AR")
        } else {
            print("⚠️ No tweets to render - all nearby tweets may already be rendered")
        }
    }
    
    func updateGuidanceMessage() {
        guard let frame = sceneView.session.currentFrame else { return }
        
        switch frame.camera.trackingState {
        case .normal:
            // Tracking is good, hide guidance
            guidanceLabel.isHidden = true
            
        case .limited(let reason):
            // Tracking is poor, show guidance
            guidanceLabel.text = "📱 Hold phone steadier for better tracking"
            guidanceLabel.textColor = .orange
            guidanceLabel.isHidden = false
            
        case .notAvailable:
            // Tracking is very poor, show guidance
            guidanceLabel.text = "❌ Move to a brighter area with more features"
            guidanceLabel.textColor = .red
            guidanceLabel.isHidden = false
        }
    }
    
    func showGuidanceForNearbyTweets() {
        guard let frame = sceneView.session.currentFrame else { return }
        
        switch frame.camera.trackingState {
        case .normal:
            // Tracking is good, tweets should appear
            guidanceLabel.text = "✨ Nearby tweet detected!"
            guidanceLabel.textColor = .green
            guidanceLabel.isHidden = false
            
            // Hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.guidanceLabel.isHidden = true
            }
            
        case .limited(let reason):
            // Tracking is poor, ask user to hold steady
            guidanceLabel.text = "📱 Hold phone steady to view nearby tweet"
            guidanceLabel.textColor = .orange
            guidanceLabel.isHidden = false
            
        case .notAvailable:
            // Tracking is very poor, ask user to move
            guidanceLabel.text = "❌ Move to a brighter area with more features"
            guidanceLabel.textColor = .red
            guidanceLabel.isHidden = false
        }
    }
    
    func setupAuthenticationUI() {
        // Safety check - ensure history button exists
        guard let historyButton = historyButton else {
            print("Warning: historyButton not yet created, skipping authentication UI setup")
            return
        }
        
        // Create user info label (prompt below history button)
        userInfoLabel = UILabel()
        userInfoLabel.text = "Please Sign In"
        userInfoLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        userInfoLabel.textColor = UIColor.white
        userInfoLabel.textAlignment = .center
        userInfoLabel.backgroundColor = UIColor.systemGray.withAlphaComponent(0.8)
        userInfoLabel.layer.cornerRadius = 10
        userInfoLabel.layer.masksToBounds = true
        userInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(userInfoLabel)
        
        // Position user info label below history button
        NSLayoutConstraint.activate([
            userInfoLabel.topAnchor.constraint(equalTo: historyButton.bottomAnchor, constant: 8),
            userInfoLabel.centerXAnchor.constraint(equalTo: historyButton.centerXAnchor),
            userInfoLabel.widthAnchor.constraint(equalToConstant: 100),
            userInfoLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Update authentication UI based on current state
        updateAuthenticationUI()
    }
    
    func updateAuthenticationUI() {
        guard let firebaseService = firebaseService else { return }
        
        // Safety check - ensure userInfoLabel exists
        guard let userInfoLabel = userInfoLabel else { return }
        
        if let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous {
            // Authenticated user
            isUserAuthenticated = true
            userInfoLabel.text = "Signed In"
            
            // Load user profile
            loadUserProfile(userId: currentUser.uid)
            
            // Load user's tweets from Firebase
            loadUserTweets()
        } else {
            // No authenticated user
            isUserAuthenticated = false
            userInfoLabel.text = "Please Sign In"
            
            // Clear local tweets when not authenticated
            tweetTexts.removeAll()
            tweetNodes.removeAll()
            
            // Update history button text and refresh table view
            updateHistoryButtonText()
            refreshTweetHistoryDisplay()
        }
    }
    
    func loadUserProfile(userId: String) {
        firebaseService.getUserProfile(userId: userId) { [weak self] userProfile, error in
            if let error = error {
                print("Error loading user profile: \(error)")
            } else if let userProfile = userProfile {
                DispatchQueue.main.async {
                    self?.currentUserProfile = userProfile
                }
            }
        }
    }
    
    func loadUserTweets() {
        guard let userId = firebaseService.getCurrentUserId() else { return }
        
        // Prevent multiple calls to this method
        if isLoadingUserTweets { return }
        isLoadingUserTweets = true
        
        // Clear existing local tweets
        tweetTexts.removeAll()
        tweetNodes.removeAll()
        
        // Fetch user's tweets from Firebase
        firebaseService.fetchNearbyTweets(latitude: 0, longitude: 0, radius: Double.infinity) { [weak self] tweets, error in
            if let error = error {
                print("Error loading user tweets: \(error)")
                self?.isLoadingUserTweets = false
                return
            }
            
            // Filter tweets to only show the current user's tweets
            let userTweets = tweets.filter { $0.userId == userId }
            
            DispatchQueue.main.async {
                // Add user's tweets to local arrays
                for tweet in userTweets {
                    self?.tweetTexts.append(tweet.text)
                }
                
                // Update history button text and refresh the history table view
                self?.updateHistoryButtonText()
                self?.refreshTweetHistoryDisplay()
                
                print("Loaded \(userTweets.count) tweets for user \(userId)")
                self?.isLoadingUserTweets = false
            }
        }
    }
    
    func setupServices() {
        // Initialize Firebase service
        firebaseService = FirebaseService()
        
        // Initialize location manager
        locationManager = LocationManager()
        locationManager.locationUpdateHandler = { [weak self] location in
            self?.onLocationUpdated(location)
        }
        
        // Start location updates immediately (no anonymous auth needed)
        locationManager.startLocationUpdates()
        
        // Update authentication UI
        updateAuthenticationUI()
    }
    
    func onLocationUpdated(_ location: CLLocation) {
        // Update mini-map with user location
        miniMapView?.updateUserLocation(location)
        
        // Load nearby tweets when location changes
        loadNearbyTweets(location: location)
    }
    
    func loadNearbyTweets(location: CLLocation) {
        // Check cooldown to prevent excessive API calls when moving
        if let lastUpdate = lastNearbyTweetsUpdate,
           Date().timeIntervalSince(lastUpdate) < nearbyTweetsUpdateCooldown {
            return
        }
        
        // Always allow auto-loading for dynamic tweet rendering as user walks
        
        firebaseService.fetchNearbyTweets(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radius: 20) { [weak self] tweets, error in
            if let error = error {
                print("Error loading nearby tweets: \(error)")
                return
            }
            
            DispatchQueue.main.async {
                self?.renderNearbyTweets(tweets)
                self?.lastNearbyTweetsUpdate = Date()
            }
        }
    }
    
    func renderNearbyTweets(_ tweets: [PersistentTweet]) {
        // Filter out tweets that are too far away (safety check)
        let currentLocation = locationManager.currentLocation
        let filteredTweets = tweets.filter { tweet in
            guard let currentLoc = currentLocation else { return true }
            
            let tweetLocation = CLLocation(latitude: tweet.latitude, longitude: tweet.longitude)
            let distance = currentLoc.distance(from: tweetLocation)
            
        // Only show tweets within 20 meters
        return distance <= 20.0
        }
        
        // Check for new tweets that haven't been notified
        let newTweets = filteredTweets.filter { tweet in
            !notifiedTweetIds.contains(tweet.id)
        }
        
        // Update nearbyTweets for button rendering
        nearbyTweets = filteredTweets
        
        // If there are new tweets, show discovery notification
        if !newTweets.isEmpty {
            showTweetsDiscoveredNotification(count: newTweets.count)
            // Mark these tweets as notified
            for tweet in newTweets {
                notifiedTweetIds.insert(tweet.id)
            }
        }
        
        // Update mini-map with nearby tweets
        miniMapView?.updateNearbyTweets(filteredTweets)
        
        // Don't render automatically - wait for button click
        return
    }
    
    // MARK: - MiniMapSearchDelegate
    
    func searchForTweetsInArea(center: CLLocationCoordinate2D, visibleRegion: MKCoordinateRegion) {
        // If this is a revert to original location (empty region), clear cache and reload original tweets
        if visibleRegion.span.latitudeDelta == 0 && visibleRegion.span.longitudeDelta == 0 {
            print("🔄 Reverting to original location tweets")
            clearRenderedTweetsCache()
            
            // Reload tweets for original location
            if let currentLocation = locationManager.currentLocation {
                loadNearbyTweets(location: currentLocation)
            }
            return
        }
        
        // Check if the search area is too far from user's current location
        if let currentLocation = locationManager.currentLocation {
            let searchLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let distanceFromUser = currentLocation.distance(from: searchLocation)
            
            print("🔍 Search area is \(Int(distanceFromUser))m from user's current location")
        }
        
        // Search for tweets in the new area
        print("🔍 ===== SEARCH REQUEST =====")
        print("🔍 Search center: \(center.latitude), \(center.longitude)")
        print("🔍 Visible region span: lat=\(visibleRegion.span.latitudeDelta), lon=\(visibleRegion.span.longitudeDelta)")
        
        // Create a location from the center coordinate
        let searchLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        
        // Calculate search radius based on visible region (use the larger span)
        let latSpan = visibleRegion.span.latitudeDelta
        let lonSpan = visibleRegion.span.longitudeDelta
        let searchRadius = max(latSpan, lonSpan) * 111000 / 2 // Convert degrees to meters, use half span as radius
        
        // Cap the search radius to reasonable limits (max 2000m for better coverage)
        let cappedRadius = min(searchRadius, 2000.0)
        
        print("🔍 Calculated search radius: \(Int(searchRadius))m")
        print("🔍 Capped search radius: \(Int(cappedRadius))m")
        print("🔍 Search location: \(searchLocation.coordinate.latitude), \(searchLocation.coordinate.longitude)")
        
        // Fetch tweets for the new area
        firebaseService.fetchNearbyTweets(latitude: searchLocation.coordinate.latitude, longitude: searchLocation.coordinate.longitude, radius: cappedRadius) { [weak self] tweets, error in
            if let error = error {
                print("❌ Error searching tweets in new area: \(error)")
                return
            }
            
            print("🔍 Firebase returned \(tweets.count) tweets")
            
            // Log the first few tweets for debugging
            for (index, tweet) in tweets.prefix(3).enumerated() {
                print("🔍 Tweet \(index + 1): '\(tweet.text)' at \(tweet.latitude), \(tweet.longitude)")
            }
            
            DispatchQueue.main.async {
                self?.renderTweetsForNewArea(tweets)
            }
        }
    }
    
    private func renderTweetsForNewArea(_ tweets: [PersistentTweet]) {
        // For searched areas, show ALL tweets in that area (not just new ones)
        // This gives users a complete view of what's available
        
        // Remove existing tweets from the searched area to avoid duplicates
        let searchedTweetIds = Set(tweets.map { $0.id })
        
        // Remove existing nodes for tweets in this area
        for node in sceneView.scene.rootNode.childNodes {
            if let nodeName = node.name,
               nodeName.hasPrefix("nearby_tweet_"),
               let tweetId = nodeName.replacingOccurrences(of: "nearby_tweet_", with: "").isEmpty ? nil : nodeName.replacingOccurrences(of: "nearby_tweet_", with: ""),
               searchedTweetIds.contains(tweetId) {
                node.removeFromParentNode()
            }
        }
        
        // Clear these IDs from rendered set since we're re-rendering them
        for tweetId in searchedTweetIds {
            renderedNearbyTweetIds.remove(tweetId)
        }
        
        // Create nodes for new tweets (keep existing ones)
        for tweet in tweets {
            let textNode = createTextNode(text: tweet.text, position: tweet.worldPosition, distance: 0.0)
            textNode.name = "nearby_tweet_\(tweet.id)"
            
            // All tweets use the same green iMessage style with white text
            // No color variations needed - consistent design throughout
            
            sceneView.scene.rootNode.addChildNode(textNode)
            
            // Mark as rendered
            renderedNearbyTweetIds.insert(tweet.id)
        }
        
        print("🔍 Rendered \(tweets.count) tweets in searched area (total rendered: \(renderedNearbyTweetIds.count))")
        
        // Update mini-map with the searched tweets
        print("🗺️ Updating mini-map with \(tweets.count) searched tweets")
        miniMapView?.updateNearbyTweets(tweets)
        print("🗺️ Mini-map update completed")
        
        // Also update the nearbyTweets array to keep it in sync
        nearbyTweets = tweets
        print("📱 Updated nearbyTweets array with \(tweets.count) tweets")
    }
    
    // Helper function to clear rendered tweets cache (useful for testing)
    func clearRenderedTweetsCache() {
        renderedNearbyTweetIds.removeAll()
        print("🧹 Cleared rendered tweets cache")
    }
    
    // MARK: - Color Picker Methods
    private func showColorPicker() {
        if colorPickerView != nil {
            colorPickerView.removeFromSuperview()
        }
        
        // Create color picker view
        colorPickerView = UIView()
        colorPickerView.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        colorPickerView.layer.cornerRadius = 12
        colorPickerView.layer.borderWidth = 2
        colorPickerView.layer.borderColor = UIColor.systemBlue.cgColor
        colorPickerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(colorPickerView)
        
        // Define colors
        let colors: [UIColor] = [
            .black, .white, .red, .orange, .yellow, .green, .blue, .purple,
            .systemPink, .systemTeal, .systemIndigo, .systemBrown
        ]
        
        let colorNames = [
            "Black", "White", "Red", "Orange", "Yellow", "Green", "Blue", "Purple",
            "Pink", "Teal", "Indigo", "Brown"
        ]
        
        // Create color buttons
        for (index, color) in colors.enumerated() {
            let colorButton = UIButton(type: .system)
            colorButton.backgroundColor = color
            colorButton.layer.cornerRadius = 15
            colorButton.layer.borderWidth = 2
            colorButton.layer.borderColor = UIColor.white.cgColor
            colorButton.tag = index
            colorButton.addTarget(self, action: #selector(colorSelected(_:)), for: .touchUpInside)
            colorButton.translatesAutoresizingMaskIntoConstraints = false
            colorPickerView.addSubview(colorButton)
            
            // Add color name label
            let nameLabel = UILabel()
            nameLabel.text = colorNames[index]
            nameLabel.textColor = UIColor.white
            nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            nameLabel.textAlignment = .center
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            colorPickerView.addSubview(nameLabel)
            
            // Position color button and label
            let row = index / 4
            let col = index % 4
            
            NSLayoutConstraint.activate([
                colorButton.topAnchor.constraint(equalTo: colorPickerView.topAnchor, constant: CGFloat(row * 50) + 20),
                colorButton.leadingAnchor.constraint(equalTo: colorPickerView.leadingAnchor, constant: CGFloat(col * 60) + 20),
                colorButton.widthAnchor.constraint(equalToConstant: 30),
                colorButton.heightAnchor.constraint(equalToConstant: 30),
                
                nameLabel.topAnchor.constraint(equalTo: colorButton.bottomAnchor, constant: 5),
                nameLabel.centerXAnchor.constraint(equalTo: colorButton.centerXAnchor),
                nameLabel.widthAnchor.constraint(equalToConstant: 50)
            ])
        }
        
        // Position color picker view below the text field
        NSLayoutConstraint.activate([
            colorPickerView.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 10),
            colorPickerView.trailingAnchor.constraint(equalTo: textField.trailingAnchor),
            colorPickerView.widthAnchor.constraint(equalToConstant: 280),
            colorPickerView.heightAnchor.constraint(equalToConstant: 200)
        ])
        
        isColorPickerVisible = true
        
        // Highlight current selection
        if let currentIndex = colors.firstIndex(of: selectedBorderColor) {
            if let currentButton = colorPickerView.viewWithTag(currentIndex) as? UIButton {
                currentButton.layer.borderWidth = 4
                currentButton.layer.borderColor = UIColor.yellow.cgColor
            }
        }
    }
    
    private func hideColorPicker() {
        colorPickerView?.removeFromSuperview()
        colorPickerView = nil
        isColorPickerVisible = false
    }
    
    @objc private func colorSelected(_ sender: UIButton) {
        let colors: [UIColor] = [
            .black, .white, .red, .orange, .yellow, .green, .blue, .purple,
            .systemPink, .systemTeal, .systemIndigo, .systemBrown
        ]
        
        let newColor = colors[sender.tag]
        selectedBorderColor = newColor
        
        // Update color picker button to show selected color
        colorPickerButton.backgroundColor = newColor
        colorPickerButton.setTitle("✓", for: .normal)
        
        // Hide color picker
        hideColorPicker()
        
        print("🎨 Selected border color: \(newColor) - Saved to UserDefaults")
    }
    
    // Helper function to get custom font with fallback
    private func getCustomFont(size: CGFloat) -> UIFont {
        // Try custom fonts in order of preference
        let customFontNames = [
            "Baliw",
            "Baliw-Regular",
            "Baliw-Bold"
        ]
        
        for fontName in customFontNames {
            if let customFont = UIFont(name: fontName, size: size) {
                print("✅ Using custom font: \(fontName)")
                return customFont
            }
        }
        
        // Fallback to system font
        print("⚠️ Custom font not found, using system font")
        return UIFont.systemFont(ofSize: size, weight: .medium)
    }
    
    // Configure modern lighting for neon effects
    private func configureModernLighting(for scene: SCNScene) {
        // Use a neutral HDR or blurred room image you include in your bundle.
        // Replace "ibl_hdr.jpg" with your asset name.
        // scene.lightingEnvironment.contents = "ibl_hdr.jpg"
        // scene.lightingEnvironment.intensity = 1.0

        let lightNode = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.intensity = 900
        light.castsShadow = true
        light.shadowRadius = 8
        light.shadowColor = UIColor.black.withAlphaComponent(0.4)
        lightNode.light = light
        lightNode.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/6, 0)
        scene.rootNode.addChildNode(lightNode)
        
        print("💡 Modern lighting configured for neon effects")
    }
    
    func createTextNode(text: String, position: SCNVector3, distance: Double) -> SCNNode {
        // Create street sign-style AR tweet
        let tweetSign = makeStreetSignNode(
            text: text,
            primaryFontName: "AvenirNext-Heavy",
            targetTextHeightMeters: 0.08,
            horizontalPaddingMeters: 0.04,
            verticalPaddingMeters: 0.024,
            textColor: .white,
            boardColor: selectedBorderColor, // Use the selected color for the board
            cornerRadiusMeters: 0.01,
            billboard: true
        )
        
        // Position the sign at the specified world position
        tweetSign.position = position
        
        // Add some animation with 3x scale
        tweetSign.scale = SCNVector3(0, 0, 0)
        let scaleAction = SCNAction.scale(to: 3.0, duration: 0.3)
        scaleAction.timingMode = .easeOut
        tweetSign.runAction(scaleAction)
        
        return tweetSign
    }
    
    @objc func enterButtonTapped() {
        guard let tweetText = textField.text, !tweetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Show alert if text is empty
            let alert = UIAlertController(title: "Empty Tweet", message: "Please enter some text for your tweet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        // Store the tweet text and wait for tap
        pendingTweetText = tweetText
        isWaitingForTap = true
        
        // Update button to show we're waiting for tap
        button.setTitle("Tap to Place", for: .normal)
        button.backgroundColor = UIColor.systemOrange
        
        // Clear text field and hide keyboard
        textField.text = ""
        textField.resignFirstResponder()
        
        // Show instruction to user
        let alert = UIAlertController(title: "Tap to Place", message: "Tap anywhere on the screen to place your tweet!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func showAuthenticationOptions() {
        let alert = UIAlertController(title: "Authentication", message: "Choose an option", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak self] _ in
            self?.showSignIn()
        })
        alert.addAction(UIAlertAction(title: "Create Account", style: .default) { [weak self] _ in
            self?.showRegistration()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func showSignOutConfirmation() {
        let alert = UIAlertController(title: "Sign Out", message: "Are you sure you want to sign out?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
            self?.signOutUser()
        })
        present(alert, animated: true)
    }
    
    @objc func authButtonTapped() {
        guard let firebaseService = firebaseService else { return }
        
        if firebaseService.isUserSignedIn() {
            // User is signed in, show sign out confirmation
            let alert = UIAlertController(title: "Sign Out", message: "Are you sure you want to sign out?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
                self?.signOutUser()
            })
            present(alert, animated: true)
        } else {
            // User is not signed in, show authentication options
            showAuthenticationOptions()
        }
    }
    
    func showSignIn() {
        let signInVC = SignInViewController()
        let navController = UINavigationController(rootViewController: signInVC)
        present(navController, animated: true)
    }
    
    func showRegistration() {
        let registrationVC = RegistrationViewController()
        let navController = UINavigationController(rootViewController: registrationVC)
        present(navController, animated: true)
    }
    
    func signOutUser() {
        guard let firebaseService = firebaseService else { return }
        
        let error = firebaseService.signOut()
        if let error = error {
            print("Error signing out: \(error)")
        } else {
            // Clear current user ID
            currentUserId = nil
            // Update UI to show sign-in state
            updateAuthenticationUI()
            print("User signed out successfully")
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc func handleAuthenticationStateChanged() {
        // Update authentication UI and refresh tweets when auth state changes
        DispatchQueue.main.async {
            self.updateAuthenticationUI()
            
            // Force refresh the history display
            self.refreshTweetHistoryDisplay()
        }
    }
    
    deinit {
        // Remove notification observer
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Helper Methods
    
    private func updateHistoryButtonText() {
        guard let historyButton = historyButton else { return }
        
        if isUserAuthenticated {
            let tweetCount = tweetTexts.count
            historyButton.setTitle("History (\(tweetCount))", for: .normal)
        } else {
            historyButton.setTitle("History", for: .normal)
        }
    }
    
    private func refreshTweetHistoryDisplay() {
        DispatchQueue.main.async {
            self.updateHistoryButtonText()
            if let historyTableView = self.historyTableView, !historyTableView.isHidden {
                historyTableView.reloadData()
            }
        }
    }
    

    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: sceneView)
        
        // Check if we're waiting to place a new tweet
        if isWaitingForTap, let tweetText = pendingTweetText {
            createTweetAtLocation(text: tweetText, location: location)
            
            // Reset state
            isWaitingForTap = false
            pendingTweetText = nil
            
            // Reset button
            button.setTitle("Enter", for: .normal)
            button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
            button.setTitleColor(UIColor.white, for: .normal)
            return
        }
        
        // Check if user tapped on an existing tweet or interaction node
        let hitTestResults = sceneView.hitTest(location, options: [:])
        
        print("🔍 Hit test results: \(hitTestResults.count)")
        for (index, hitTestResult) in hitTestResults.enumerated() {
            let node = hitTestResult.node
            print("🔍 Hit \(index): node name = \(node.name ?? "nil")")
            
            // Check if tapped on an interaction node
            if let nodeName = node.name, nodeName.hasPrefix("interaction_") {
                let tweetId = nodeName.replacingOccurrences(of: "interaction_", with: "")
                print("🎯 Tapped on interaction node for tweet: \(tweetId)")
                handleInteractionNodeTap(tweetId: tweetId, location: location)
                return
            }
            
            // Find the parent tweet node by traversing up the hierarchy
            var currentNode = node
            while currentNode.parent != nil {
                if let nodeName = currentNode.name,
                   (nodeName.hasPrefix("nearby_tweet_") || nodeName.hasPrefix("my_tweet_")) {
                    
                    // Extract tweet ID from node name
                    let tweetId = nodeName.replacingOccurrences(of: "nearby_tweet_", with: "")
                        .replacingOccurrences(of: "my_tweet_", with: "")
                    
                    if !tweetId.isEmpty {
                        handleTweetTap(tweetId: tweetId, node: currentNode)
                    }
                    return
                }
                currentNode = currentNode.parent!
            }
        }
    }
    
    // MARK: - Tweet Interaction Methods
    
    func handleInteractionNodeTap(tweetId: String, location: CGPoint) {
        print("🎯 Handling interaction tap for tweet: \(tweetId)")
        
        // Get the hit test result to find the exact 3D position
        let hitTestResults = sceneView.hitTest(location, options: [:])
        
        for hitTestResult in hitTestResults {
            if let nodeName = hitTestResult.node.name, nodeName == "interaction_\(tweetId)" {
                // Get the local coordinates within the plane
                let localCoordinates = hitTestResult.localCoordinates
                print("🎯 Local coordinates: x=\(localCoordinates.x), y=\(localCoordinates.y)")
                
                // The plane is 0.25 wide, so left half is < 0, right half is > 0
                if localCoordinates.x < 0 {
                    // Like button tapped (left side)
                    print("❤️ Like button tapped - coordinates: x=\(localCoordinates.x)")
                    handleLikeTapped(tweetId: tweetId)
                } else {
                    // Comment button tapped (right side)
                    print("💬 Comment button tapped - coordinates: x=\(localCoordinates.x)")
                    handleCommentTapped(tweetId: tweetId)
                }
                return
            }
        }
        
        print("❌ No interaction node found in hit test results")
    }
    
    func handleTweetTap(tweetId: String, node: SCNNode) {
        // Find the tweet data - check both nearby tweets and our own tweets
        var tweet = nearbyTweets.first { $0.id == tweetId }
        
        // If not found in nearby tweets, it might be one of our own tweets
        // For our own tweets, we'll create a basic PersistentTweet from the node
        if tweet == nil {
            // Extract text from the node to create a basic tweet
            var tweetText = ""
            for childNode in node.childNodes {
                if let textGeometry = childNode.geometry as? SCNText {
                    tweetText = textGeometry.string as? String ?? ""
                    break
                }
            }
            
            if !tweetText.isEmpty {
                // Create a basic PersistentTweet for our own tweet
                tweet = PersistentTweet(
                    id: tweetId,
                    text: tweetText,
                    latitude: 0, // We don't have location data for display purposes
                    longitude: 0,
                    altitude: nil,
                    worldPosition: node.position,
                    userId: firebaseService.getCurrentUserId() ?? "",
                    timestamp: Date(),
                    isPublic: true,
                    likes: [],
                    comments: []
                )
            }
        }
        
        if let tweet = tweet {
            selectedTweetId = tweetId
            showTweetInteractionView(for: tweet, at: node)
        }
    }
    
    func showTweetInteractionView(for tweet: PersistentTweet, at node: SCNNode) {
        // Remove any existing interaction view
        hideTweetInteractionView()
        
        // Create interaction view as a 3D node below the tweet
        let interactionView = TweetInteractionView()
        interactionView.configure(with: tweet, isLiked: tweet.isLikedBy(userId: firebaseService.getCurrentUserId() ?? ""))
        
        // Set up callbacks
        interactionView.onLikeTapped = { [weak self] tweetId in
            self?.handleLikeTapped(tweetId: tweetId)
        }
        
        interactionView.onCommentTapped = { [weak self] tweetId in
            self?.handleCommentTapped(tweetId: tweetId)
        }
        
        // Create a 3D plane to hold the interaction view (rectangle shape)
        let interactionPlane = SCNPlane(width: 0.4, height: 0.15) // Wider rectangle (0.25 * 1.6 = 0.4, 0.24 * 0.625 = 0.15)
        let interactionMaterial = SCNMaterial()
        
        // Convert UIView to UIImage for the material (rectangle shape)
        interactionView.frame = CGRect(x: 0, y: 0, width: 400, height: 150) // Rectangle: 400x150 (matches 0.4x0.15 plane)
        interactionView.layoutIfNeeded()
        
        // Force the view to render properly
        interactionView.setNeedsDisplay()
        interactionView.setNeedsLayout()
        
        // Add a small delay to ensure the view is fully rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let renderer = UIGraphicsImageRenderer(size: interactionView.bounds.size)
            let image = renderer.image { context in
                interactionView.drawHierarchy(in: interactionView.bounds, afterScreenUpdates: true)
            }
            
            interactionMaterial.diffuse.contents = image
            interactionMaterial.lightingModel = .constant
            interactionMaterial.isDoubleSided = true
            interactionPlane.materials = [interactionMaterial]
        }
        
        // Create the 3D node
        let interactionNode = SCNNode(geometry: interactionPlane)
        
        // Position it below the tweet node
        // Use a fixed offset below the tweet instead of calculating height
        let interactionOffset: Float = -0.08 // Much smaller gap for closer positioning
        
        // Position relative to the tweet node (not absolute world position)
        interactionNode.position = SCNVector3(0, interactionOffset, 0)
        
        // Make it face the camera (billboard)
        interactionNode.constraints = [SCNBillboardConstraint()]
        
        // Enable hit testing for this node
        interactionNode.isHidden = false
        
        // Add as child of the tweet node so they move together
        node.addChildNode(interactionNode)
        
        // Store reference with the node for cleanup
        interactionNode.name = "interaction_\(tweet.id)"
        tweetInteractionViews[tweet.id] = interactionView
        
        print("✅ Created interaction node for tweet \(tweet.id) at position \(interactionNode.position)")
        
        // Add entrance animation
        interactionNode.scale = SCNVector3(0, 0, 0)
        let scaleAction = SCNAction.scale(to: 1.0, duration: 0.3)
        scaleAction.timingMode = .easeOut
        interactionNode.runAction(scaleAction)
        
        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.hideTweetInteractionView()
        }
    }
    
    func hideTweetInteractionView() {
        // Remove all interaction nodes from the 3D scene with animation
        for (tweetId, _) in tweetInteractionViews {
            let interactionNodeName = "interaction_\(tweetId)"
            
            // Find and remove the interaction node from the scene
            // Now searching in all nodes since interaction nodes are children of tweet nodes
            sceneView.scene.rootNode.enumerateChildNodes { (node, _) in
                if node.name == interactionNodeName {
                    // Add fade-out animation
                    let fadeAction = SCNAction.fadeOut(duration: 0.3)
                    let removeAction = SCNAction.removeFromParentNode()
                    let sequence = SCNAction.sequence([fadeAction, removeAction])
                    node.runAction(sequence)
                }
            }
        }
        
        tweetInteractionViews.removeAll()
    }
    
    func handleLikeTapped(tweetId: String) {
        guard let userId = firebaseService.getCurrentUserId() else {
            print("❌ User not authenticated - cannot like tweet")
            return
        }
        
        print("❤️ Attempting to like tweet \(tweetId) by user \(userId)")
        
        firebaseService.toggleLike(tweetId: tweetId, userId: userId) { [weak self] error in
            if let error = error {
                print("❌ Error toggling like: \(error)")
            } else {
                print("✅ Successfully toggled like for tweet \(tweetId)")
                // Update the UI
                DispatchQueue.main.async {
                    self?.updateTweetLikeState(tweetId: tweetId)
                }
            }
        }
    }
    
    func handleCommentTapped(tweetId: String) {
        selectedTweetId = tweetId
        showCommentInput()
    }
    
    func showCommentInput() {
        commentInputView?.isHidden = false
        commentInputView?.onSendComment = { [weak self] commentText in
            self?.sendComment(commentText)
        }
    }
    
    func hideCommentInput() {
        commentInputView?.isHidden = true
    }
    
    func sendComment(_ text: String) {
        guard let tweetId = selectedTweetId,
              let userId = firebaseService.getCurrentUserId(),
              let userProfile = currentUserProfile else {
            print("Missing required data for comment")
            return
        }
        
        firebaseService.addComment(tweetId: tweetId, text: text, userId: userId, username: userProfile.username) { [weak self] error in
            if let error = error {
                print("Error adding comment: \(error)")
            } else {
                DispatchQueue.main.async {
                    self?.hideCommentInput()
                    self?.showComments(for: tweetId)
                }
            }
        }
    }
    
    func showComments(for tweetId: String) {
        firebaseService.getComments(tweetId: tweetId) { [weak self] comments, error in
            if let error = error {
                print("Error fetching comments: \(error)")
            } else {
                DispatchQueue.main.async {
                    self?.commentDisplayView?.configure(with: comments)
                    self?.commentDisplayView?.isHidden = false
                }
            }
        }
    }
    
    func hideCommentDisplay() {
        commentDisplayView?.isHidden = true
    }
    
    func updateTweetLikeState(tweetId: String) {
        // Find the tweet in nearby tweets and update its like state
        if let index = nearbyTweets.firstIndex(where: { $0.id == tweetId }) {
            // Fetch the updated tweet data from Firebase
            firebaseService.fetchNearbyTweets(latitude: 0, longitude: 0, radius: Double.infinity) { [weak self] tweets, error in
                if let error = error {
                    print("Error fetching updated tweet data: \(error)")
                    return
                }
                
                // Find the specific tweet that was liked
                if let updatedTweet = tweets.first(where: { $0.id == tweetId }) {
                    DispatchQueue.main.async {
                        // Update the tweet in our array
                        self?.nearbyTweets[index] = updatedTweet
                        
                        // Update the interaction view if it's currently visible
                        if let interactionView = self?.tweetInteractionViews[tweetId] {
                            let isLiked = updatedTweet.isLikedBy(userId: self?.firebaseService.getCurrentUserId() ?? "")
                            interactionView.updateLikeState(isLiked: isLiked, likeCount: updatedTweet.likeCount)
                            interactionView.updateCommentCount(updatedTweet.commentCount)
                        }
                        
                        print("✅ Updated like state for tweet \(tweetId): \(updatedTweet.likeCount) likes")
                    }
                }
            }
        } else {
            // For our own tweets, we need to refresh the specific tweet
            // Since our tweets might not be in nearbyTweets, we'll refresh all nearby tweets
            refreshNearbyTweets()
        }
    }
    
    func refreshNearbyTweets() {
        guard let location = locationManager.currentLocation else { return }
        loadNearbyTweets(location: location)
    }
    
    func createTweetAtLocation(text: String, location: CGPoint) {
        // Perform hit test to find where to place the tweet
        let hitTestResults = sceneView.hitTest(location, types: [.featurePoint, .estimatedHorizontalPlane])
        
        guard let hitTestResult = hitTestResults.first else {
            // If no hit test result, place at a default distance in front of camera
            createTweet(text: text)
            return
        }
        
        // Get the world position from the hit test
        let worldPosition = hitTestResult.worldTransform.columns.3
        let tweetPosition = SCNVector3(worldPosition.x, worldPosition.y, worldPosition.z)
        
        // Create and save persistent tweet
        savePersistentTweet(text: text, position: tweetPosition)
        
        // Create visual node
        let textNode = createTextNode(text: text, position: tweetPosition, distance: 0.0)
        textNode.name = "my_tweet_\(UUID().uuidString)"
        
        // Store reference to the tweet node (text will be added in savePersistentTweet)
        tweetNodes.append(textNode)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(textNode)
    }
    
    func createTweet(text: String) {
        guard let pointOfView = sceneView.pointOfView else { return }
        
        // Get camera position and direction
        let mat = pointOfView.transform
        let dir = SCNVector3(-1 * mat.m31, -1 * mat.m32, -1 * mat.m33)
        
        // Calculate position at screen center height (same Y as camera, but in front)
        let cameraPosition = pointOfView.position
        let tweetPosition = SCNVector3(
            cameraPosition.x + (dir.x * 0.5),
            cameraPosition.y, // Same height as camera
            cameraPosition.z + (dir.z * 0.5)
        )
        
        // Create and save persistent tweet
        savePersistentTweet(text: text, position: tweetPosition)
        
        // Create visual node
        let textNode = createTextNode(text: text, position: tweetPosition, distance: 0.0)
        textNode.name = "my_tweet_\(UUID().uuidString)"
        
        // Store reference to the tweet node (text will be added in savePersistentTweet)
        tweetNodes.append(textNode)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(textNode)
    }
    
    func savePersistentTweet(text: String, position: SCNVector3) {
        // Use authenticated user ID if available, otherwise fall back to anonymous ID
        let userId = firebaseService.getCurrentUserId() ?? currentUserId
        
        guard let userId = userId,
              let location = locationManager.currentLocation else {
            print("Cannot save tweet: missing user ID or location")
            return
        }
        
        let tweet = PersistentTweet(
            id: UUID().uuidString,
            text: text,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            worldPosition: position,
            userId: userId,
            timestamp: Date(),
            isPublic: true,
            likes: [],
            comments: []
        )
        
        firebaseService.saveTweet(tweet) { [weak self] error in
            if let error = error {
                print("Error saving tweet: \(error)")
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Error", message: "Failed to save tweet. Please try again.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            } else {
                print("Tweet saved successfully")
                // Add to local arrays for history
                DispatchQueue.main.async {
                    self?.tweetTexts.append(text)
                    
                    // Update history button text and refresh table view
                    self?.refreshTweetHistoryDisplay()
                }
            }
        }
    }
    
    @objc func historyButtonTapped() {
        isHistoryVisible.toggle()
        
        if isHistoryVisible {
            historyTableView.isHidden = false
            historyTableView.reloadData()
            
            // Animate in
            historyTableView.alpha = 0
            UIView.animate(withDuration: 0.3) {
                self.historyTableView.alpha = 1
            }
        } else {
            // Animate out
            UIView.animate(withDuration: 0.3) {
                self.historyTableView.alpha = 0
            } completion: { _ in
                self.historyTableView.isHidden = true
            }
        }
    }
    
    func deleteTweet(at index: Int) {
        guard index < tweetNodes.count && index < tweetTexts.count else { return }
        
        // Remove from arrays
        let nodeToRemove = tweetNodes.remove(at: index)
        tweetTexts.remove(at: index)
        
        // Add fade out animation
        let fadeAction = SCNAction.fadeOut(duration: 0.3)
        let removeAction = SCNAction.removeFromParentNode()
        let sequence = SCNAction.sequence([fadeAction, removeAction])
        nodeToRemove.runAction(sequence)
        
        // Update history button text and reload table view
        updateHistoryButtonText()
        historyTableView.reloadData()
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isUserAuthenticated {
            // Show tweets + sign out button
            return tweetTexts.count + 1
        } else {
            // Show sign-in button as first row when not authenticated
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TweetCell", for: indexPath)
        
        if isUserAuthenticated {
            if indexPath.row < tweetTexts.count {
                // Show tweet content
                cell.textLabel?.text = tweetTexts[indexPath.row]
                cell.textLabel?.textColor = UIColor.systemGreen
                cell.textLabel?.font = getCustomFont(size: 16)
                cell.backgroundColor = UIColor.clear
                cell.selectionStyle = .none
                
                // Style the cell background
                let backgroundView = UIView()
                backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                backgroundView.layer.cornerRadius = 8
                backgroundView.layer.borderWidth = 1
                backgroundView.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.3).cgColor
                cell.backgroundView = backgroundView
                
                // Add delete button to cell
                let deleteButton = UIButton(type: .system)
                deleteButton.setTitle("🗑️", for: .normal)
                deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
                deleteButton.tag = indexPath.row
                deleteButton.addTarget(self, action: #selector(deleteButtonTapped(_:)), for: .touchUpInside)
                deleteButton.frame = CGRect(x: cell.contentView.frame.width - 40, y: 5, width: 30, height: 30)
                cell.contentView.addSubview(deleteButton)
            } else {
                // Show sign-out button as last row
                cell.textLabel?.text = "Sign Out"
                cell.textLabel?.textColor = UIColor.white
                cell.textLabel?.font = getCustomFont(size: 16)
                cell.backgroundColor = UIColor.clear
                cell.selectionStyle = .default
                
                // Style the cell background for sign-out button
                let backgroundView = UIView()
                backgroundView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
                backgroundView.layer.cornerRadius = 8
                backgroundView.layer.borderWidth = 1
                backgroundView.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.5).cgColor
                cell.backgroundView = backgroundView
                
                // Center the text
                cell.textLabel?.textAlignment = .center
            }
        } else {
            // Show sign-in button as first row
            cell.textLabel?.text = "Sign In"
            cell.textLabel?.textColor = UIColor.white
            cell.textLabel?.font = getCustomFont(size: 16)
            cell.backgroundColor = UIColor.clear
            cell.selectionStyle = .default
            
            // Style the cell background for sign-in button
            let backgroundView = UIView()
            backgroundView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
            backgroundView.layer.cornerRadius = 8
            backgroundView.layer.borderWidth = 1
            backgroundView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
            cell.backgroundView = backgroundView
            
            // Center the text
            cell.textLabel?.textAlignment = .center
        }
        
        return cell
    }
    
    @objc func deleteButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        deleteTweet(at: index)
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if isUserAuthenticated {
            if indexPath.row == tweetTexts.count {
                // Sign-out button tapped
                showSignOutConfirmation()
            }
        } else {
            // Show authentication options when sign-in button is tapped
            showAuthenticationOptions()
        }
    }
    
    @objc func colorPickerButtonTapped() {
        if isColorPickerVisible {
            hideColorPicker()
        } else {
            showColorPicker()
        }
    }
    
    // MARK: - UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        enterButtonTapped()
        return true
    }
    
    // MARK: - ARSCNViewDelegate
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateGuidanceMessage()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
    }
    
    // Function to refresh all existing tweet nodes with the new iMessage bubble design
    func refreshAllExistingTweets() {
        // Get all existing tweet nodes
        let existingTweetNodes = sceneView.scene.rootNode.childNodes.filter { node in
            if let nodeName = node.name {
                return nodeName.hasPrefix("my_tweet_") || nodeName.hasPrefix("nearby_tweet_")
            }
            return false
        }
        
        for node in existingTweetNodes {
            // Find the corresponding tweet text
            if let nodeName = node.name {
                // Extract the tweet ID from the node name
                let tweetId = nodeName.replacingOccurrences(of: "my_tweet_", with: "")
                    .replacingOccurrences(of: "nearby_tweet_", with: "")
                
                // Find the tweet text from our arrays
                var tweetText = ""
                if let index = tweetNodes.firstIndex(where: { $0.name == nodeName }) {
                    tweetText = tweetTexts[index]
                } else {
                    // If not in our arrays, try to get from the node's child text
                    for childNode in node.childNodes {
                        if let textGeometry = childNode.geometry as? SCNText {
                            tweetText = textGeometry.string as? String ?? ""
                            break
                        }
                    }
                }
                
                if !tweetText.isEmpty {
                    // Create a new text node with the updated design
                    let newTextNode = createTextNode(text: tweetText, position: node.position, distance: 0.0)
                    newTextNode.name = nodeName // Keep the original name
                    
                    // Remove the old node
                    node.removeFromParentNode()
                    
                    // Add the new node
                    sceneView.scene.rootNode.addChildNode(newTextNode)
                    
                    // Update our arrays if this was a tracked tweet
                    if let index = tweetNodes.firstIndex(where: { $0.name == nodeName }) {
                        tweetNodes[index] = newTextNode
                    }
                }
            }
        }
        
        print("✅ All existing tweets refreshed with new iMessage bubble design.")
    }
    
    // MARK: - Keyboard Handling
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIKeyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        // Move comment input view above keyboard
        let keyboardHeight = keyboardFrame.height
        commentInputViewBottomConstraint?.constant = -keyboardHeight - 20
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIKeyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        // Move comment input view back to original position
        commentInputViewBottomConstraint?.constant = -20
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
}

