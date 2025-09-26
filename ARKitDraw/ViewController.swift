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
import AVFoundation
import Photos
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

class ViewController: UIViewController, ARSCNViewDelegate, UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource, MiniMapSearchDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var textField: UITextField!
    
    // Array to track all tweet nodes and their text
    private var tweetNodes: [SCNNode] = []
    private var userTweets: [PersistentTweet] = []
    
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
    private var pendingTweetColor: UIColor = UIColor.black
    
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
    
    // MARK: - Drawing Functionality
    private var drawButton: UIButton!
    private var resetButton: UIButton!
    private var saveDrawingButton: UIButton!
    private var cameraButton: UIButton!
    
    private var isDrawingMode = false
    private var currentDrawingNode: SCNNode?
    private var drawingPoints: [SCNVector3] = []
    private var isCurrentlyDrawing = false
    private var lastCameraPosition: SCNVector3?
    private var drawingStartTime: Date?
    private var completedDrawingStrokes: [SCNNode] = [] // Track completed strokes for reset functionality
    
    // MARK: - Drawing Data Tracking
    private var currentDrawingStrokes: [DrawingStroke] = [] // All strokes in current drawing
    private var currentStrokePoints: [SCNVector3] = [] // Points in current stroke being drawn
    private var currentStrokeColor: UIColor = .white // Current stroke color
    private var currentStrokeWidth: Float = 0.01 // Current stroke width
    
    // MARK: - Like and Comment Functionality
    private var tweetInteractionViews: [String: TweetInteractionView] = [:]
    private var commentInputView: CommentInputView?
    private var commentInputViewBottomConstraint: NSLayoutConstraint?
    private var commentDisplayView: CommentDisplayView?
    private var selectedTweetId: String?
    private var currentUserProfile: UserProfile?
    
    // Image picker properties
    private var selectedImage: UIImage?
    private var isWaitingForImagePlacement = false
    
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
        button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.75)
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
        
        // Create right view container with both image picker and color picker buttons
        let rightViewContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        
        // Add image picker button
        let imagePickerButton = UIButton(type: .system)
        imagePickerButton.setImage(UIImage(systemName: "plus"), for: .normal)
        imagePickerButton.tintColor = UIColor.white
        imagePickerButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        imagePickerButton.layer.cornerRadius = 15
        imagePickerButton.layer.masksToBounds = true
        imagePickerButton.layer.borderWidth = 1
        imagePickerButton.layer.borderColor = UIColor.white.cgColor
        imagePickerButton.addTarget(self, action: #selector(imagePickerButtonTapped), for: .touchUpInside)
        
        rightViewContainer.addSubview(imagePickerButton)
        rightViewContainer.addSubview(colorPickerButton)
        
        // Position buttons in right view container
        imagePickerButton.frame = CGRect(x: 10, y: 5, width: 30, height: 30)
        colorPickerButton.frame = CGRect(x: 50, y: 5, width: 30, height: 30)
        
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
        
        // Setup Draw button
        setupDrawButton()
        
        // Setup Reset button
        setupResetButton()
        
        // Setup Save Drawing button
        setupSaveDrawingButton()
        
        // Setup Camera button
        setupCameraButton()
        
        // Hide draw and reset buttons
        drawButton.isHidden = true
        resetButton.isHidden = true
        
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
            miniMapView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
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
        seeTweetsButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        seeTweetsButton.setTitleColor(.white, for: .normal)
        seeTweetsButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        seeTweetsButton.layer.cornerRadius = 12
        seeTweetsButton.layer.shadowColor = UIColor.black.cgColor
        seeTweetsButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        seeTweetsButton.layer.shadowOpacity = 0.6
        seeTweetsButton.layer.shadowRadius = 8
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
    
    func setupDrawButton() {
        // Create Draw button
        drawButton = UIButton(type: .system)
        drawButton.setTitle("Draw", for: .normal)
        drawButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        drawButton.setTitleColor(.white, for: .normal)
        drawButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        drawButton.layer.cornerRadius = 12
        drawButton.layer.shadowColor = UIColor.black.cgColor
        drawButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        drawButton.layer.shadowOpacity = 0.6
        drawButton.layer.shadowRadius = 8
        drawButton.addTarget(self, action: #selector(drawButtonPressed), for: .touchDown)
        drawButton.addTarget(self, action: #selector(drawButtonReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        drawButton.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(drawButton)
        
        // Position below the Enter button on the right side
        NSLayoutConstraint.activate([
            drawButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            drawButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 20),
            drawButton.widthAnchor.constraint(equalToConstant: 100),
            drawButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    func setupResetButton() {
        // Create Reset button
        resetButton = UIButton(type: .system)
        resetButton.setTitle("↺", for: .normal)
        resetButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        resetButton.layer.cornerRadius = 12
        resetButton.layer.shadowColor = UIColor.black.cgColor
        resetButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        resetButton.layer.shadowOpacity = 0.6
        resetButton.layer.shadowRadius = 8
        resetButton.addTarget(self, action: #selector(resetButtonTapped), for: .touchUpInside)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(resetButton)
        
        // Position below the Draw button on the right side
        NSLayoutConstraint.activate([
            resetButton.trailingAnchor.constraint(equalTo: drawButton.trailingAnchor),
            resetButton.topAnchor.constraint(equalTo: drawButton.bottomAnchor, constant: 10),
            resetButton.widthAnchor.constraint(equalToConstant: 50),
            resetButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    func setupSaveDrawingButton() {
        // Create Save Drawing button
        saveDrawingButton = UIButton(type: .system)
        saveDrawingButton.setTitle("Save Drawing", for: .normal)
        saveDrawingButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.4)
        saveDrawingButton.setTitleColor(.white, for: .normal)
        saveDrawingButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        saveDrawingButton.layer.cornerRadius = 8
        saveDrawingButton.layer.shadowColor = UIColor.systemBlue.cgColor
        saveDrawingButton.layer.shadowOpacity = 0.3
        saveDrawingButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        saveDrawingButton.layer.shadowRadius = 4
        saveDrawingButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to view
        view.addSubview(saveDrawingButton)
        
        // Position below the reset button
        NSLayoutConstraint.activate([
            saveDrawingButton.centerXAnchor.constraint(equalTo: resetButton.centerXAnchor),
            saveDrawingButton.topAnchor.constraint(equalTo: resetButton.bottomAnchor, constant: 10),
            saveDrawingButton.widthAnchor.constraint(equalToConstant: 80),
            saveDrawingButton.heightAnchor.constraint(equalToConstant: 35)
        ])
        
        // Add action
        saveDrawingButton.addTarget(self, action: #selector(saveDrawingButtonTapped), for: .touchUpInside)
        
        // Initially hidden
        saveDrawingButton.isHidden = true
    }
    
    func setupCameraButton() {
        // Create Camera button
        cameraButton = UIButton(type: .system)
        cameraButton.setTitle("📷", for: .normal)
        cameraButton.backgroundColor = UIColor.systemGreen // Green circular background
        cameraButton.setTitleColor(.white, for: .normal)
        cameraButton.titleLabel?.font = UIFont.systemFont(ofSize: 30, weight: .medium) // Larger icon size
        cameraButton.layer.cornerRadius = 25 // Circular background (half of width/height)
        cameraButton.contentVerticalAlignment = .center // Center vertically
        cameraButton.contentHorizontalAlignment = .center // Center horizontally
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to view
        view.addSubview(cameraButton)
        
        // Position above the See Tweets button
        NSLayoutConstraint.activate([
            cameraButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cameraButton.bottomAnchor.constraint(equalTo: seeTweetsButton.topAnchor, constant: -20),
            cameraButton.widthAnchor.constraint(equalToConstant: 50), // Larger width for bigger icon
            cameraButton.heightAnchor.constraint(equalToConstant: 50) // Larger height for bigger icon
        ])
        
        // Add action
        cameraButton.addTarget(self, action: #selector(cameraButtonTapped), for: .touchUpInside)
    }
    
    
    @objc func saveDrawingButtonTapped() {
        print("🎨 Save drawing button tapped")
        
        guard !currentDrawingStrokes.isEmpty else {
            print("🎨 No drawing strokes to save")
            guidanceLabel.text = "No drawing to save"
            guidanceLabel.textColor = .systemRed
            guidanceLabel.isHidden = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.guidanceLabel.isHidden = true
            }
            return
        }
        
        print("🎨 Found \(currentDrawingStrokes.count) drawing strokes")
        
        // Get current location
        guard let currentLocation = locationManager.currentLocation else {
            print("🎨 Location not available")
            guidanceLabel.text = "Location not available"
            guidanceLabel.textColor = .systemRed
            guidanceLabel.isHidden = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.guidanceLabel.isHidden = true
            }
            return
        }
        
        // Get the drawing origin position (where the drawing actually is)
        guard let firstStroke = currentDrawingStrokes.first,
              let firstPoint = firstStroke.points.first else {
            print("🎨 No drawing points available")
            guidanceLabel.text = "No drawing points available"
            guidanceLabel.textColor = .systemRed
            guidanceLabel.isHidden = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.guidanceLabel.isHidden = true
            }
            return
        }
        
        // Use the first stroke's first point as the drawing origin
        let drawingOrigin = firstPoint
        
        print("🎨 Creating drawing tweet with location: \(currentLocation.coordinate)")
        print("🎨 Drawing origin position: \(drawingOrigin)")
        
        do {
            // Create drawing tweet
            let drawingTweet = PersistentTweet(
                id: UUID().uuidString,
                text: "🎨 3D Drawing",
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude,
                altitude: currentLocation.altitude,
                worldPosition: drawingOrigin,
                userId: firebaseService.getCurrentUserId() ?? "anonymous",
                timestamp: Date(),
                isPublic: true,
                likes: [],
                comments: [],
                screenPosition: CGPoint(x: 0, y: 0),
                color: UIColor.black,
                isDrawing: true,
                drawingStrokes: currentDrawingStrokes,
                hasImage: false,
                imageURL: nil,
                imageWidth: nil,
                imageHeight: nil
            )
            
            print("🎨 Drawing tweet created successfully")
            
            // Save to Firebase
            firebaseService.saveTweet(drawingTweet) { [weak self] error in
                DispatchQueue.main.async {
                    if error == nil {
                        print("🎨 Drawing saved successfully to Firebase")
                        self?.guidanceLabel.text = "Drawing saved successfully!"
                        self?.guidanceLabel.textColor = .systemGreen
                        self?.guidanceLabel.isHidden = false
                        
                        // Clear current drawing data
                        self?.currentDrawingStrokes.removeAll()
                        self?.saveDrawingButton.isHidden = true
                        
                        // Hide after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self?.guidanceLabel.isHidden = true
                        }
                    } else {
                        print("🎨 Failed to save drawing to Firebase: \(error?.localizedDescription ?? "Unknown error")")
                        self?.guidanceLabel.text = "Failed to save drawing"
                        self?.guidanceLabel.textColor = .systemRed
                        self?.guidanceLabel.isHidden = false
                        
                        // Hide after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self?.guidanceLabel.isHidden = true
                        }
                    }
                }
            }
            
        } catch {
            print("🎨 Error creating drawing tweet: \(error.localizedDescription)")
            guidanceLabel.text = "Error creating drawing: \(error.localizedDescription)"
            guidanceLabel.textColor = .systemRed
            guidanceLabel.isHidden = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.guidanceLabel.isHidden = true
            }
        }
    }
    
    @objc func cameraButtonTapped() {
        print("📷 Camera button tapped - capturing AR scene")

        // Capture the current AR scene view
        let screenshot = sceneView.snapshot()

        // Save to photo library
        UIImageWriteToSavedPhotosAlbum(screenshot, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)

        // Show feedback
        guidanceLabel.text = "📷 Photo saved to camera roll!"
        guidanceLabel.textColor = .systemGreen
        guidanceLabel.isHidden = false

        // Hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.guidanceLabel.isHidden = true
        }
    }
    
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            print("📷 Error saving image: \(error.localizedDescription)")
            guidanceLabel.text = "Failed to save photo"
            guidanceLabel.textColor = .systemRed
        } else {
            print("📷 Photo saved successfully to camera roll")
            guidanceLabel.text = "📷 Photo saved successfully!"
            guidanceLabel.textColor = .systemGreen
        }
        
        guidanceLabel.isHidden = false
        
        // Hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.guidanceLabel.isHidden = true
        }
    }
    
    
    func showTweetsDiscoveredNotification(count: Int) {
        let message = count == 1 ? "New tweet detected, Click 'See Tweets' button to view it" : "New tweets detected, Click 'See Tweets' button to view them"
        guidanceLabel.text = message
        guidanceLabel.textColor = .white
        guidanceLabel.isHidden = false
        
        // Hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.guidanceLabel.isHidden = true
        }
    }
    
    func showStabilityGuidance() {
        guidanceLabel.text = "Hold phone steady for a few secs"
        guidanceLabel.textColor = .white
        guidanceLabel.isHidden = false
        
        // Hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.guidanceLabel.isHidden = true
        }
    }
    
    @objc func drawButtonPressed() {
        // Button pressed down - start drawing
        print("🎨 Draw button PRESSED - Starting drawing")
        
        isDrawingMode = true
        drawButton.setTitle("Drawing...", for: .normal)
        drawButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.4)
        
        // Show drawing guidance
        guidanceLabel.text = "Move phone around to draw, release to stop"
        guidanceLabel.textColor = .white
        guidanceLabel.isHidden = false
        
        // Hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.guidanceLabel.isHidden = true
        }
        
        // Start camera-based drawing
        startCameraDrawing()
    }
    
    @objc func drawButtonReleased() {
        // Button released - stop drawing
        print("🎨 Draw button RELEASED - Stopping drawing")
        
        isDrawingMode = false
        drawButton.setTitle("Draw", for: .normal)
        drawButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        
        // Finish current drawing if any
        finishCurrentDrawing()
        stopCameraDrawing()
    }
    
    @objc func resetButtonTapped() {
        // Remove the most recent completed drawing stroke
        if !completedDrawingStrokes.isEmpty {
            let lastStroke = completedDrawingStrokes.removeLast()
            lastStroke.removeFromParentNode()
            print("🎨 Removed last stroke. Remaining strokes: \(completedDrawingStrokes.count)")
            
            // Also remove the corresponding stroke data
            if !currentDrawingStrokes.isEmpty {
                let removedStrokeData = currentDrawingStrokes.removeLast()
                print("📝 Removed stroke data with \(removedStrokeData.points.count) points")
            }
            
            // Hide save button if no strokes remain
            if currentDrawingStrokes.isEmpty {
                saveDrawingButton.isHidden = true
            }
            
            // Show feedback to user
            guidanceLabel.text = "Removed last stroke"
            guidanceLabel.textColor = .white
            guidanceLabel.isHidden = false
            
            // Hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.guidanceLabel.isHidden = true
            }
        } else {
            // No strokes to remove
            guidanceLabel.text = "No strokes to remove"
            guidanceLabel.textColor = .systemRed
            guidanceLabel.isHidden = false
            
            // Hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.guidanceLabel.isHidden = true
            }
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
            let tweetLocation = CLLocation(latitude: tweet.latitude, longitude: tweet.longitude)
            let distance = currentLoc.distance(from: tweetLocation)
            return !renderedNearbyTweetIds.contains(tweet.id) && distance <= 20.0
        }
        
        print("🎯 Tweets to render: \(tweetsToRender.count)")
        
        if tweetsToRender.isEmpty {
            print("ℹ️ All nearby tweets are already rendered. No new tweets to show.")
            return
        }
        
        // Render each tweet
        for tweet in tweetsToRender {
            let tweetLocation = CLLocation(latitude: tweet.latitude, longitude: tweet.longitude)
            let distance = currentLoc.distance(from: tweetLocation)
            
            print("📱 Rendering tweet: '\(tweet.text)' at distance: \(Int(distance))m")
            
            // Check if this is a drawing tweet
            if tweet.isDrawing && !tweet.drawingStrokes.isEmpty {
                print("🎨 Rendering drawing tweet with \(tweet.drawingStrokes.count) strokes")
                renderDrawingTweet(tweet, at: tweetLocation, distance: distance)
            } else if tweet.hasImage, let imageURL = tweet.imageURL {
                // Image tweet
                print("🖼️ Rendering image tweet")
                let screenRelativePosition = calculatePositionFromScreenCoordinates(
                    screenX: tweet.screenPositionX,
                    screenY: tweet.screenPositionY
                )
                
                loadImageFromURL(imageURL) { [weak self] image in
                    if let image = image {
                        let imageNode = self?.createImageNode(image: image, at: screenRelativePosition)
                        if let imageNode = imageNode {
                            imageNode.name = "nearby_tweet_\(tweet.id)"
                            self?.sceneView.scene.rootNode.addChildNode(imageNode)
                        }
                    }
                }
            } else {
                // Regular text tweet
                // Use screen position for better discovery experience
                let screenRelativePosition = calculatePositionFromScreenCoordinates(
                    screenX: tweet.screenPositionX,
                    screenY: tweet.screenPositionY
                )
                
                // Debug logging for tweet discovery
                print("🔍 Tweet '\(tweet.text)' screen position: (\(tweet.screenPositionX), \(tweet.screenPositionY))")
                print("🔍 Calculated 3D position: \(screenRelativePosition)")
                
                let textNode = createTextNode(text: tweet.text, position: screenRelativePosition, distance: distance, color: tweet.color)
                textNode.name = "nearby_tweet_\(tweet.id)"
                
                sceneView.scene.rootNode.addChildNode(textNode)
            }
            
            renderedNearbyTweetIds.insert(tweet.id)
        }
        
        print("✨ Successfully rendered \(tweetsToRender.count) new tweets in AR")
    }
    
    // MARK: - Drawing Tweet Rendering
    func renderDrawingTweet(_ tweet: PersistentTweet, at location: CLLocation, distance: Double) {
        // Create a container node for all the drawing strokes
        let drawingContainer = SCNNode()
        drawingContainer.name = "nearby_drawing_\(tweet.id)"
        
        // Position drawing at its original AR world coordinates
        drawingContainer.position = tweet.worldPosition
        
        print("🎨 Drawing positioned at original AR world coordinates: \(tweet.worldPosition)")
        
        
        // Recreate each stroke from the stored data
        for (strokeIndex, stroke) in tweet.drawingStrokes.enumerated() {
            print("🎨 Rendering stroke \(strokeIndex + 1) with \(stroke.points.count) points")
            
            // Create a node for this stroke
            let strokeNode = SCNNode()
            strokeNode.name = "stroke_\(strokeIndex)"
            
            // Recreate the stroke geometry from the stored points
            if stroke.points.count >= 2 {
                // Create line segments between consecutive points
                for i in 0..<(stroke.points.count - 1) {
                    let startPoint = stroke.points[i]
                    let endPoint = stroke.points[i + 1]
                    
                    let lineSegment = createDrawingLine(from: startPoint, to: endPoint)
                    
                    // Create a full material with all 3D properties to maintain proper depth
                    let material = SCNMaterial()
                    material.diffuse.contents = stroke.color  // Use saved color
                    material.lightingModel = .constant       // Constant lighting to show true colors
                    material.isDoubleSided = true
                    material.emission.contents = stroke.color
                    material.emission.intensity = 0.2
                    material.specular.contents = UIColor.white
                    material.shininess = 0.5
                    
                    lineSegment.geometry?.materials = [material]
                    strokeNode.addChildNode(lineSegment)
                }
            }
            
            drawingContainer.addChildNode(strokeNode)
        }
        
        // Add the entire drawing to the scene
        sceneView.scene.rootNode.addChildNode(drawingContainer)
        
        print("🎨 Successfully rendered drawing with \(tweet.drawingStrokes.count) strokes")
    }
    
    func updateGuidanceMessage() {
        guard let frame = sceneView.session.currentFrame else { return }
        
        switch frame.camera.trackingState {
        case .normal:
            // Tracking is good, hide guidance
            guidanceLabel.isHidden = true
            
        case .limited(let reason):
            // Tracking is poor, but no guidance message needed
            guidanceLabel.isHidden = true
            
        case .notAvailable:
            // Tracking is very poor, show guidance
            guidanceLabel.text = "❌ Move to a brighter area with more features"
            guidanceLabel.textColor = .white
            guidanceLabel.isHidden = false
        }
    }
    
    func showGuidanceForNearbyTweets() {
        guard let frame = sceneView.session.currentFrame else { return }
        
        switch frame.camera.trackingState {
        case .normal:
            // Tracking is good, tweets should appear
            guidanceLabel.text = "✨ Nearby tweet detected!"
            guidanceLabel.textColor = .white
            guidanceLabel.isHidden = false
            
            // Hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.guidanceLabel.isHidden = true
            }
            
        case .limited(let reason):
            // Tracking is poor, ask user to hold steady
            guidanceLabel.text = "📱 Hold phone steady to view nearby tweet"
            guidanceLabel.textColor = .white
            guidanceLabel.isHidden = false
            
        case .notAvailable:
            // Tracking is very poor, ask user to move
            guidanceLabel.text = "❌ Move to a brighter area with more features"
            guidanceLabel.textColor = .white
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
            userTweets.removeAll()
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
        userTweets.removeAll()
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
                // Store full tweet objects
                self?.userTweets = userTweets
                
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
        
        // Don't clear rendered tweets cache automatically
        // This prevents re-rendering of already visible tweets
        
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
        // For searched areas, ONLY show tweets on the map
        // Do NOT render 3D nodes - let the normal nearby tweet system handle that
        
        print("🔍 Showing \(tweets.count) tweets from searched area on map only")
        
        // Update mini-map with ALL searched tweets (for map display)
        print("🗺️ Updating mini-map with \(tweets.count) searched tweets")
        miniMapView?.updateNearbyTweets(tweets)
        print("🗺️ Mini-map update completed")
        
        // DON'T update nearbyTweets array - keep it for actual nearby tweets only
        // DON'T render any 3D nodes - let loadNearbyTweets() handle that based on proximity
        print("🔍 Map updated - 3D rendering will be handled by normal nearby tweet system")
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
        
        // Set the pending tweet color (for the next tweet to be created)
        pendingTweetColor = newColor
        
        // Also update the global color for backward compatibility
        selectedBorderColor = newColor
        
        // Update color picker button to show selected color
        colorPickerButton.backgroundColor = newColor
        colorPickerButton.setTitle("✓", for: .normal)
        
        // Hide color picker
        hideColorPicker()
        
        print("🎨 Selected color for next tweet: \(newColor)")
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
    
    func calculatePositionFromScreenCoordinates(screenX: Float, screenY: Float) -> SCNVector3 {
        guard let frame = sceneView.session.currentFrame else {
            print("🔍 No AR frame available, using fallback position")
            return SCNVector3(0, 0, -2) // Fallback position
        }
        
        let cameraTransform = frame.camera.transform
        let currentCameraPosition = SCNVector3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y - 0.4,  // Lower camera position by 0.4m (15 inches)
            cameraTransform.columns.3.z
        )
        
        print("🔍 Camera position: \(currentCameraPosition)")
        print("🔍 Input screen coordinates: (\(screenX), \(screenY))")
        
        // Get camera forward direction
        let forward = SCNVector3(
            -cameraTransform.columns.2.x,
            -cameraTransform.columns.2.y,
            -cameraTransform.columns.2.z
        )
        
        // Get camera right direction
        let right = SCNVector3(
            cameraTransform.columns.0.x,
            cameraTransform.columns.0.y,
            cameraTransform.columns.0.z
        )
        
        // Get camera up direction
        let up = SCNVector3(
            cameraTransform.columns.1.x,
            cameraTransform.columns.1.y,
            cameraTransform.columns.1.z
        )
        
        // Convert screen coordinates to 3D offset
        let horizontalSpread: Float = 1.0  // How far left/right tweets can appear
        let verticalSpread: Float = 0.5    // How far up/down tweets can appear
        let distanceInFront: Float = 2.0   // Distance in front of camera
        
        let offsetX = screenX * horizontalSpread
        let offsetY = screenY * verticalSpread - 0.4  // Lower tweets by 0.4m (15 inches)
        let offsetZ = distanceInFront
        
        // Calculate final position
        let finalPosition = SCNVector3(
            currentCameraPosition.x + right.x * offsetX + up.x * offsetY + forward.x * offsetZ,
            currentCameraPosition.y + right.y * offsetX + up.y * offsetY + forward.y * offsetZ,
            currentCameraPosition.z + right.z * offsetX + up.z * offsetY + forward.z * offsetZ
        )
        
        print("🔍 Calculated offsets: (\(offsetX), \(offsetY), \(offsetZ))")
        print("🔍 Final 3D position: \(finalPosition)")
        
        return finalPosition
    }
    
    func createTextNode(text: String, position: SCNVector3, distance: Double, color: UIColor = UIColor.black) -> SCNNode {
        // Create street sign-style AR tweet
        let tweetSign = makeStreetSignNode(
            text: text,
            primaryFontName: "AvenirNext-Heavy",
            targetTextHeightMeters: 0.08,
            horizontalPaddingMeters: 0.04,
            verticalPaddingMeters: 0.024,
            textColor: .white,
            boardColor: color, // Use the specific color for this tweet
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
        print("🔘 Enter button tapped")
        print("🔘 Selected image: \(selectedImage != nil ? "YES" : "NO")")
        print("🔘 Waiting for image placement: \(isWaitingForImagePlacement)")
        
        // Check if we have an image to place
        if let image = selectedImage, isWaitingForImagePlacement {
            print("🔘 Placing image in AR")
            placeImageInAR(image: image)
            return
        }
        
        // Original text tweet logic
        guard let tweetText = textField.text, !tweetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("🔘 No text entered, showing empty tweet alert")
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
    
    // MARK: - Image Picker Methods
    
    @objc func imagePickerButtonTapped() {
        print("➕ Image picker button tapped!")
        
        // Check if we have an image selected and are waiting for placement
        if let image = selectedImage, isWaitingForImagePlacement {
            print("➕ Image already selected, calling enterButtonTapped")
            // User wants to place the selected image
            enterButtonTapped()
            return
        }
        
        print("➕ Showing image picker options")
        // Show image picker options
        let alert = UIAlertController(title: "Add Image", message: "Choose how you'd like to add an image", preferredStyle: .actionSheet)
        
        // Camera option
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { _ in
                print("📸 Camera option selected")
                self.presentImagePicker(sourceType: .camera)
            })
        }
        
        // Photo library option
        alert.addAction(UIAlertAction(title: "Choose from Library", style: .default) { _ in
            print("📸 Photo library option selected")
            print("📸 .photoLibrary raw value: \(UIImagePickerController.SourceType.photoLibrary.rawValue)")
            self.presentImagePicker(sourceType: .photoLibrary)
        })
        
        // Remove selected image option
        if selectedImage != nil {
            alert.addAction(UIAlertAction(title: "Remove Image", style: .destructive) { _ in
                self.selectedImage = nil
                self.isWaitingForImagePlacement = false
                self.updateButtonState()
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func presentImagePicker(sourceType: UIImagePickerController.SourceType) {
        print("📸 Presenting image picker with source type: \(sourceType.rawValue)")
        print("📸 Source type enum: \(sourceType)")
        
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = sourceType
        imagePicker.allowsEditing = true
        
        print("📸 Image picker delegate set to: \(imagePicker.delegate)")
        print("📸 Image picker source type: \(imagePicker.sourceType.rawValue)")
        print("📸 Image picker allows editing: \(imagePicker.allowsEditing)")
        print("📸 Self: \(self)")
        print("📸 Delegate type: \(type(of: imagePicker.delegate))")
        
        present(imagePicker, animated: true) {
            print("📸 Image picker presentation completed")
        }
    }
    
    private func placeImageInAR(image: UIImage) {
        // Update button to show we're waiting for tap
        button.setTitle("Tap to Place", for: .normal)
        button.backgroundColor = UIColor.systemOrange
        
        // Clear text field and hide keyboard
        textField.text = ""
        textField.resignFirstResponder()
        
        // Show instruction to user
        let alert = UIAlertController(title: "Tap to Place", message: "Tap anywhere on the screen to place your image!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func updateButtonState() {
        if selectedImage != nil && isWaitingForImagePlacement {
            button.setTitle("Place Image", for: .normal)
            button.backgroundColor = UIColor.systemOrange
        } else {
            button.setTitle("Enter", for: .normal)
            button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.75)
        }
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        print("🖼️ Image picker delegate method called!")
        print("🖼️ Picker: \(picker)")
        print("🖼️ Info: \(info)")
        print("🖼️ Info keys: \(info.keys)")
        picker.dismiss(animated: true)
        
        print("🖼️ Image picker finished, info keys: \(info.keys)")
        
        if let editedImage = info["UIImagePickerControllerEditedImage"] as? UIImage {
            selectedImage = editedImage
            print("🖼️ Selected edited image")
        } else if let originalImage = info["UIImagePickerControllerOriginalImage"] as? UIImage {
            selectedImage = originalImage
            print("🖼️ Selected original image")
        } else {
            print("🖼️ No image found in info")
        }
        
        if selectedImage != nil {
            isWaitingForImagePlacement = true
            updateButtonState()
            print("🖼️ Image selected, waiting for placement: \(isWaitingForImagePlacement)")
            
            // Show instruction to user
            let alert = UIAlertController(title: "Image Selected", message: "Tap 'Enter' to place your image in AR space!", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } else {
            print("🖼️ No image selected")
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        print("🖼️ Image picker cancelled")
        picker.dismiss(animated: true) {
            print("🖼️ Image picker dismiss completed")
        }
    }
    
    // MARK: - AR Image Placement
    
    private func placeImageAtLocation(location: CGPoint, image: UIImage) {
        // Convert screen coordinates to world coordinates
        let hitTestResults = sceneView.hitTest(location, types: .existingPlaneUsingExtent)
        
        if let hitResult = hitTestResults.first {
            let worldPosition = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y,
                hitResult.worldTransform.columns.3.z
            )
            
            // Create image node
            let imageNode = createImageNode(image: image, at: worldPosition)
            sceneView.scene.rootNode.addChildNode(imageNode)
            tweetNodes.append(imageNode)
            
            // Get current location
            guard let currentLocation = locationManager.currentLocation else {
                print("No location available")
                return
            }
            
            // Upload image to Firebase Storage first
            firebaseService.uploadImage(image) { [weak self] imageURL, error in
                if let error = error {
                    print("Error uploading image: \(error)")
                    return
                }
                
                guard let imageURL = imageURL,
                      let userId = self?.firebaseService.getCurrentUserId() else {
                    print("Failed to get image URL or user ID")
                    return
                }
                
                // Create tweet with image
                let tweet = PersistentTweet(
                    id: UUID().uuidString,
                    text: "", // Empty text for image-only tweets
                    latitude: currentLocation.coordinate.latitude,
                    longitude: currentLocation.coordinate.longitude,
                    altitude: currentLocation.altitude,
                    worldPosition: worldPosition,
                    userId: userId,
                    timestamp: Date(),
                    isPublic: true,
                    likes: [],
                    comments: [],
                    screenPosition: CGPoint(x: 0, y: 0),
                    color: UIColor.black,
                    isDrawing: false,
                    drawingStrokes: [],
                    hasImage: true,
                    imageURL: imageURL,
                    imageWidth: Float(image.size.width),
                    imageHeight: Float(image.size.height)
                )
                
                // Save to Firebase
                self?.firebaseService.saveTweet(tweet) { error in
                    if let error = error {
                        print("Error saving image tweet: \(error)")
                    } else {
                        print("Image tweet saved successfully")
                        self?.userTweets.append(tweet)
                    }
                }
            }
            
            // Reset state
            selectedImage = nil
            isWaitingForImagePlacement = false
            updateButtonState()
        } else {
            // If no plane detected, place at a default distance in front of camera
            guard let pointOfView = sceneView.pointOfView else { return }
            
            // Get camera position and direction
            let mat = pointOfView.transform
            let dir = SCNVector3(-1 * mat.m31, -1 * mat.m32, -1 * mat.m33)
            
            // Calculate position in front of camera
            let distance: Float = 1.0
            let worldPosition = SCNVector3(
                pointOfView.position.x + dir.x * distance,
                pointOfView.position.y + dir.y * distance,
                pointOfView.position.z + dir.z * distance
            )
            
            // Create image node
            let imageNode = createImageNode(image: image, at: worldPosition)
            sceneView.scene.rootNode.addChildNode(imageNode)
            tweetNodes.append(imageNode)
            
            // Get current location
            guard let currentLocation = locationManager.currentLocation else {
                print("No location available")
                return
            }
            
            // Upload image to Firebase Storage first
            firebaseService.uploadImage(image) { [weak self] imageURL, error in
                if let error = error {
                    print("Error uploading image: \(error)")
                    return
                }
                
                guard let imageURL = imageURL,
                      let userId = self?.firebaseService.getCurrentUserId() else {
                    print("Failed to get image URL or user ID")
                    return
                }
                
                // Create tweet with image
                let tweet = PersistentTweet(
                    id: UUID().uuidString,
                    text: "", // Empty text for image-only tweets
                    latitude: currentLocation.coordinate.latitude,
                    longitude: currentLocation.coordinate.longitude,
                    altitude: currentLocation.altitude,
                    worldPosition: worldPosition,
                    userId: userId,
                    timestamp: Date(),
                    isPublic: true,
                    likes: [],
                    comments: [],
                    screenPosition: CGPoint(x: 0, y: 0),
                    color: UIColor.black,
                    isDrawing: false,
                    drawingStrokes: [],
                    hasImage: true,
                    imageURL: imageURL,
                    imageWidth: Float(image.size.width),
                    imageHeight: Float(image.size.height)
                )
                
                // Save to Firebase
                self?.firebaseService.saveTweet(tweet) { error in
                    if let error = error {
                        print("Error saving image tweet: \(error)")
                    } else {
                        print("Image tweet saved successfully")
                        self?.userTweets.append(tweet)
                    }
                }
            }
            
            // Reset state
            selectedImage = nil
            isWaitingForImagePlacement = false
            updateButtonState()
        }
    }
    
    private func createImageNode(image: UIImage, at position: SCNVector3) -> SCNNode {
        print("🖼️ Creating image node with image size: \(image.size)")
        
        // Create a plane geometry for the image
        let plane = SCNPlane(width: 1.0, height: 1.0)
        
        // Set the image as the material
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.isDoubleSided = true
        plane.materials = [material]
        
        print("🖼️ Material diffuse contents set: \(material.diffuse.contents != nil)")
        
        // Create the node
        let imageNode = SCNNode(geometry: plane)
        imageNode.position = position
        
        // Make it face the camera using billboard constraint (same as text tweets)
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [.Y] // Only rotate around Y axis (keep upright)
        imageNode.constraints = [billboardConstraint]
        
        print("🖼️ Image node created at position: \(position)")
        
        return imageNode
    }
    
    private func displayTweetsInAR(tweets: [PersistentTweet]) {
        print("🔄 Displaying \(tweets.count) tweets in AR space")
        
        for tweet in tweets {
            if tweet.hasImage, let imageURL = tweet.imageURL {
                // Load image from URL and create node
                loadImageFromURL(imageURL) { [weak self] image in
                    if let image = image {
                        let imageNode = self?.createImageNode(image: image, at: tweet.worldPosition)
                        if let imageNode = imageNode {
                            self?.sceneView.scene.rootNode.addChildNode(imageNode)
                            self?.tweetNodes.append(imageNode)
                        }
                    }
                }
            } else if !tweet.text.isEmpty {
                // Create text node for text tweets
                let textNode = createTextNode(text: tweet.text, position: tweet.worldPosition, distance: 0.5, color: tweet.color)
                sceneView.scene.rootNode.addChildNode(textNode)
                tweetNodes.append(textNode)
            }
        }
    }
    
    private func loadImageFromURL(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error loading image: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                print("Failed to create image from data")
                completion(nil)
                return
            }
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
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
            let tweetCount = userTweets.count
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
    
    // MARK: - Camera-Based Drawing Functions
    
    func startCameraDrawing() {
        print("🎨 Starting camera-based drawing")
        // Reset any existing drawing state
        finishCurrentDrawing()
        lastCameraPosition = nil
        drawingStartTime = nil
        
        // Automatically start drawing when entering drawing mode
        startNewCameraDrawing()
    }
    
    func stopCameraDrawing() {
        print("🎨 Stopping camera-based drawing")
        finishCurrentDrawing()
        lastCameraPosition = nil
        drawingStartTime = nil
    }
    
    
    func startNewCameraDrawing() {
        guard let pointOfView = sceneView.pointOfView else { return }
        
        finishCurrentDrawing()
        isCurrentlyDrawing = true
        drawingStartTime = Date()
        
        // Get current camera position
        let cameraPosition = SCNVector3(
            pointOfView.position.x,
            pointOfView.position.y,
            pointOfView.position.z
        )
        
        drawingPoints = [cameraPosition]
        lastCameraPosition = cameraPosition
        
        // Create a new drawing node
        currentDrawingNode = SCNNode()
        currentDrawingNode?.name = "drawing_\\(UUID().uuidString)"
        sceneView.scene.rootNode.addChildNode(currentDrawingNode!)
        
        print("🎨 Started new camera drawing at: \(cameraPosition)")
    }
    
    func updateCameraDrawing() {
        guard isCurrentlyDrawing,
              let drawingNode = currentDrawingNode,
              let pointOfView = sceneView.pointOfView else { return }
        
        // Get current camera position
        let currentCameraPosition = SCNVector3(
            pointOfView.position.x,
            pointOfView.position.y,
            pointOfView.position.z
        )
        
        // Only add point if camera moved significantly (larger threshold for smoother paint-like strokes)
        if let lastPos = lastCameraPosition {
            let distance = currentCameraPosition.distance(vector: lastPos)
            if distance > 0.05 { // 5cm threshold for smoother paint-like strokes
                addCameraPointToDrawing(currentCameraPosition)
                lastCameraPosition = currentCameraPosition
            }
        } else {
            lastCameraPosition = currentCameraPosition
        }
    }
    
    func addCameraPointToDrawing(_ position: SCNVector3) {
        guard isCurrentlyDrawing, let drawingNode = currentDrawingNode else { return }
        
        drawingPoints.append(position)
        
        // Also track for stroke data
        currentStrokePoints.append(position)
        
        // If we have at least 2 points, create a line segment
        if drawingPoints.count >= 2 {
            let startPoint = drawingPoints[drawingPoints.count - 2]
            let endPoint = drawingPoints[drawingPoints.count - 1]
            let lineSegment = createDrawingLine(from: startPoint, to: endPoint)
            drawingNode.addChildNode(lineSegment)
        }
    }
    
    func finishCurrentDrawing() {
        if isCurrentlyDrawing {
            // Store the completed drawing stroke before clearing it
            if let completedStroke = currentDrawingNode {
                completedDrawingStrokes.append(completedStroke)
                print("🎨 Stored completed stroke. Total strokes: \(completedDrawingStrokes.count)")
            }
            
            // Create and store the DrawingStroke data
            if !currentStrokePoints.isEmpty {
                let stroke = DrawingStroke(
                    points: currentStrokePoints,
                    color: currentStrokeColor,
                    width: currentStrokeWidth,
                    timestamp: Date()
                )
                currentDrawingStrokes.append(stroke)
                print("📝 Stored stroke data with \(currentStrokePoints.count) points")
                
                // Show save button if we have strokes
                DispatchQueue.main.async {
                    self.saveDrawingButton.isHidden = false
                }
            }
            
            isCurrentlyDrawing = false
            currentDrawingNode = nil
            drawingPoints.removeAll()
            currentStrokePoints.removeAll()
            lastCameraPosition = nil
            drawingStartTime = nil
        }
    }
    
    func createDrawingLine(from startPoint: SCNVector3, to endPoint: SCNVector3) -> SCNNode {
        // Use SceneKit-only quad approach for thick strokes
        let strokeWidth: Float = 0.01 // 1cm thick strokes
        let strokeGeometry = createThickStrokeGeometry(from: startPoint, to: endPoint, width: strokeWidth)
        let strokeNode = SCNNode(geometry: strokeGeometry)
        
        // NO BILLBOARD CONSTRAINT - let's see what happens!
        // let billboardConstraint = SCNBillboardConstraint()
        // billboardConstraint.freeAxes = [.Y] // Only rotate around Y axis
        // strokeNode.constraints = [billboardConstraint]
        
        return strokeNode
    }
    
    func createThickStrokeGeometry(from startPoint: SCNVector3, to endPoint: SCNVector3, width: Float) -> SCNGeometry {
        // Calculate the direction vector and length
        let direction = SCNVector3(
            endPoint.x - startPoint.x,
            endPoint.y - startPoint.y,
            endPoint.z - startPoint.z
        )
        let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        
        // Create vertices for a quad (4 vertices = 2 triangles)
        let halfWidth = width / 2.0
        
        // For simplicity, we'll create a quad that extends in the Y direction
        // The billboard constraint will make it face the camera
        let vertices: [SCNVector3] = [
            // First triangle
            SCNVector3(startPoint.x - halfWidth, startPoint.y, startPoint.z),
            SCNVector3(startPoint.x + halfWidth, startPoint.y, startPoint.z),
            SCNVector3(endPoint.x - halfWidth, endPoint.y, endPoint.z),
            // Second triangle (shared vertices)
            SCNVector3(endPoint.x + halfWidth, endPoint.y, endPoint.z)
        ]
        
        // Create vertex data
        let vertexData = NSData(bytes: vertices, length: MemoryLayout<SCNVector3>.size * vertices.count) as Data
        let vertexSource = SCNGeometrySource(data: vertexData,
                                           semantic: .vertex,
                                           vectorCount: vertices.count,
                                           usesFloatComponents: true,
                                           componentsPerVector: 3,
                                           bytesPerComponent: MemoryLayout<Float>.size,
                                           dataOffset: 0,
                                           dataStride: MemoryLayout<SCNVector3>.stride)
        
        // Create indices for two triangles
        let indices: [UInt32] = [
            0, 1, 2,  // First triangle
            1, 3, 2   // Second triangle
        ]
        
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        
        // Set up material
        let material = SCNMaterial()
        material.diffuse.contents = selectedBorderColor
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.emission.contents = selectedBorderColor
        material.emission.intensity = 0.2
        geometry.materials = [material]
        
        return geometry
    }    
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: sceneView)
        
        
        // Check if we're waiting to place an image
        if let image = selectedImage, isWaitingForImagePlacement {
            placeImageAtLocation(location: location, image: image)
            return
        }
        
        // Check if we're waiting to place a new tweet
        if isWaitingForTap, let tweetText = pendingTweetText {
            createTweetAtLocation(text: tweetText, location: location)
            
            // Reset state
            isWaitingForTap = false
            pendingTweetText = nil
            
            // Reset button
            button.setTitle("Enter", for: .normal)
            button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.75)
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
                if let nodeName = currentNode.name {
                    // Check for tweet or drawing nodes
                    if nodeName.hasPrefix("nearby_tweet_") || nodeName.hasPrefix("my_tweet_") || 
                       nodeName.hasPrefix("nearby_drawing_") || nodeName.hasPrefix("my_drawing_") {
                        
                        // Extract tweet ID from node name
                        let tweetId = nodeName.replacingOccurrences(of: "nearby_tweet_", with: "")
                            .replacingOccurrences(of: "my_tweet_", with: "")
                            .replacingOccurrences(of: "nearby_drawing_", with: "")
                            .replacingOccurrences(of: "my_drawing_", with: "")
                        
                        if !tweetId.isEmpty {
                            handleTweetTap(tweetId: tweetId, node: currentNode)
                        }
                        return
                    }
                    // Check for stroke nodes within drawings
                    else if nodeName.hasPrefix("stroke_") {
                        // Find the parent drawing node
                        var parentNode = currentNode.parent
                        while parentNode != nil {
                            if let parentName = parentNode?.name,
                               (parentName.hasPrefix("nearby_drawing_") || parentName.hasPrefix("my_drawing_")) {
                                
                                // Extract tweet ID from parent drawing node
                                let tweetId = parentName.replacingOccurrences(of: "nearby_drawing_", with: "")
                                    .replacingOccurrences(of: "my_drawing_", with: "")
                                
                                if !tweetId.isEmpty {
                                    handleTweetTap(tweetId: tweetId, node: parentNode!)
                                }
                                return
                            }
                            parentNode = parentNode?.parent
                        }
                    }
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
            // Check if this is a drawing node
            if node.name?.hasPrefix("nearby_drawing_") == true || node.name?.hasPrefix("my_drawing_") == true {
                // For drawing tweets, we need to find the original tweet data
                // This shouldn't happen for nearby tweets, but handle it gracefully
                print("🎨 Drawing tweet tapped, but original data not found")
                return
            }
            
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
                    comments: [],
                    screenPosition: CGPoint(x: 0, y: 0),
                    color: UIColor.black,
                    isDrawing: false,
                    drawingStrokes: [],
                    hasImage: false,
                    imageURL: nil,
                    imageWidth: nil,
                    imageHeight: nil
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
        
        // First, check if there are existing comments and show them
        showComments(for: tweetId)
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
                    
                    // Also show the input field so user can add new comments
                    self?.showCommentInput()
                }
            }
        }
    }
    
    func hideCommentDisplay() {
        commentDisplayView?.isHidden = true
        hideCommentInput()
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
        
        // Convert screen tap to normalized coordinates (-1 to 1)
        let normalizedX = (location.x / sceneView.bounds.width) * 2 - 1
        let normalizedY = (location.y / sceneView.bounds.height) * 2 - 1
        let screenPosition = CGPoint(x: normalizedX, y: normalizedY)
        
        // Debug logging for tweet creation
        print("🔍 Screen tap at: \(location)")
        print("🔍 Normalized coordinates: (\(normalizedX), \(normalizedY))")
        print("🔍 Screen position stored: \(screenPosition)")
        
        // Create and save persistent tweet with screen position and color
        savePersistentTweet(text: text, position: tweetPosition, screenPosition: screenPosition, color: pendingTweetColor)
        
        // Create visual node with the selected color
        let textNode = createTextNode(text: text, position: tweetPosition, distance: 0.0, color: pendingTweetColor)
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
        let currentCameraPosition = SCNVector3(
            pointOfView.position.x,
            pointOfView.position.y,
            pointOfView.position.z
        )
        let tweetPosition = SCNVector3(
            currentCameraPosition.x + (dir.x * 0.5),
            currentCameraPosition.y, // Same height as camera
            currentCameraPosition.z + (dir.z * 0.5)
        )
        
        // Create and save persistent tweet with color
        savePersistentTweet(text: text, position: tweetPosition, color: pendingTweetColor)
        
        // Create visual node with the selected color
        let textNode = createTextNode(text: text, position: tweetPosition, distance: 0.0, color: pendingTweetColor)
        textNode.name = "my_tweet_\(UUID().uuidString)"
        
        // Store reference to the tweet node (text will be added in savePersistentTweet)
        tweetNodes.append(textNode)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(textNode)
    }
    
    func savePersistentTweet(text: String, position: SCNVector3, screenPosition: CGPoint = CGPoint(x: 0, y: 0), color: UIColor = UIColor.black) {
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
            comments: [],
            screenPosition: screenPosition,
            color: color,
            isDrawing: false,
            drawingStrokes: [],
            hasImage: false,
            imageURL: nil,
            imageWidth: nil,
            imageHeight: nil
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
                    self?.userTweets.append(tweet)
                    
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
        print("🗑️ deleteTweet called with index: \(index)")
        print("🗑️ userTweets.count: \(userTweets.count)")
        
        guard index < userTweets.count else { 
            print("❌ Delete failed: index \(index) out of bounds for userTweets")
            return 
        }
        
        let tweetToDelete = userTweets[index]
        print("🗑️ Deleting tweet: \(tweetToDelete.text) with ID: \(tweetToDelete.id)")
        
        // Delete from Firebase first
        firebaseService.deleteTweet(tweetId: tweetToDelete.id) { [weak self] error in
            if let error = error {
                print("❌ Error deleting tweet from Firebase: \(error)")
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Error", message: "Failed to delete tweet from server. Please try again.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
                return
            }
            
            print("✅ Tweet deleted from Firebase successfully")
            
            DispatchQueue.main.async {
                // Remove from local array
                self?.userTweets.remove(at: index)
                
                // Remove from 3D scene if it exists
                if index < self?.tweetNodes.count ?? 0 {
                    let nodeToRemove = self?.tweetNodes.remove(at: index)
                    let fadeAction = SCNAction.fadeOut(duration: 0.3)
                    let removeAction = SCNAction.removeFromParentNode()
                    let sequence = SCNAction.sequence([fadeAction, removeAction])
                    nodeToRemove?.runAction(sequence)
                }
                
                print("🗑️ After removal - userTweets.count: \(self?.userTweets.count ?? 0)")
                
                // Update UI
                self?.updateHistoryButtonText()
                self?.historyTableView.reloadData()
                print("✅ Delete completed and table reloaded")
            }
        }
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isUserAuthenticated {
            // Show tweets + sign out button
            return userTweets.count + 1
        } else {
            // Show sign-in button as first row when not authenticated
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TweetCell", for: indexPath)
        
        if isUserAuthenticated {
            if indexPath.row < userTweets.count {
                // Show tweet content
                cell.textLabel?.text = userTweets[indexPath.row].text
                cell.textLabel?.textColor = UIColor.white
                cell.textLabel?.font = getCustomFont(size: 16)
                cell.textLabel?.textAlignment = .left
                cell.backgroundColor = UIColor.black
                cell.selectionStyle = .none
                
                // Style the cell background
                let backgroundView = UIView()
                backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
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
        print("🗑️ Delete button tapped! Index: \(index)")
        print("🗑️ Tweet text at index \(index): \(userTweets[index].text)")
        print("🗑️ Total tweets before delete: \(userTweets.count)")
        deleteTweet(at: index)
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if isUserAuthenticated {
            if indexPath.row == userTweets.count {
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
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Update camera-based drawing when in drawing mode
        if isDrawingMode && isCurrentlyDrawing {
            updateCameraDrawing()
        }
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
                    // Check if this is one of our user tweets
                    if index < userTweets.count {
                        tweetText = userTweets[index].text
                    } else {
                        // Fallback to getting text from the node itself
                        for childNode in node.childNodes {
                            if let textGeometry = childNode.geometry as? SCNText {
                                tweetText = textGeometry.string as? String ?? ""
                                break
                            }
                        }
                    }
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
                    // Find the tweet color from our arrays
                    var tweetColor = UIColor.black // Default color
                    if let index = tweetNodes.firstIndex(where: { $0.name == nodeName }) {
                        // Check if this is one of our user tweets
                        if index < userTweets.count {
                            tweetColor = userTweets[index].color
                        }
                    } else {
                        // For nearby tweets, find the color
                        if let nearbyTweet = nearbyTweets.first(where: { "nearby_tweet_\($0.id)" == nodeName }) {
                            tweetColor = nearbyTweet.color
                        }
                    }
                    
                    // Create a new text node with the updated design and correct color
                    let newTextNode = createTextNode(text: tweetText, position: node.position, distance: 0.0, color: tweetColor)
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



