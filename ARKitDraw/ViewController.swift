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
        
        // Setup UI
        setupUI()
        
        // Initialize Firebase and Location services
        setupServices()
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
        
        // Stop location updates
        locationManager?.stopLocationUpdates()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    func setupUI() {
        // Configure text field
        textField.placeholder = "What's your thought here?"
        textField.borderStyle = .none
        textField.backgroundColor = UIColor.white
        textField.textColor = UIColor.black
        textField.layer.cornerRadius = 12
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemGray4.cgColor
        textField.font = UIFont.systemFont(ofSize: 16, weight: .medium)
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
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        
        // Add button action
        button.addTarget(self, action: #selector(enterButtonTapped), for: .touchUpInside)
        
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
    
    func setupServices() {
        // Initialize Firebase service
        firebaseService = FirebaseService()
        
        // Initialize location manager
        locationManager = LocationManager()
        locationManager.locationUpdateHandler = { [weak self] location in
            self?.onLocationUpdated(location)
        }
        
        // Sign in anonymously to Firebase
        firebaseService.signInAnonymously { [weak self] userId, error in
            if let error = error {
                print("Firebase sign in error: \(error)")
                return
            }
            
            self?.currentUserId = userId
            print("Signed in with user ID: \(userId ?? "unknown")")
            
            // Start location updates after authentication
            DispatchQueue.main.async {
                self?.locationManager.startLocationUpdates()
            }
        }
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
        
        // Don't auto-load tweets if we're in search mode (user manually searched an area)
        // This prevents search results from being cleared by location updates
        if !renderedNearbyTweetIds.isEmpty {
            print("🔄 Skipping auto-load - user has searched tweets visible")
            return
        }
        
        firebaseService.fetchNearbyTweets(location: location, radius: 100) { [weak self] tweets, error in
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
            
            // Only show tweets within 5km (5000m) as a reasonable limit
            let isWithinReasonableDistance = distance <= 5000
            
            if !isWithinReasonableDistance {
                print("⚠️ Filtered out distant tweet: '\(tweet.text)' at \(Int(distance))m away")
            }
            
            return isWithinReasonableDistance
        }
        
        print("🔍 Filtered \(tweets.count) tweets down to \(filteredTweets.count) within reasonable distance")
        
        // Only render tweets that haven't been rendered before
        var newTweets: [PersistentTweet] = []
        
        for tweet in filteredTweets {
            if !renderedNearbyTweetIds.contains(tweet.id) {
                newTweets.append(tweet)
                renderedNearbyTweetIds.insert(tweet.id)
            }
        }
        
        // Only create nodes for new tweets
        for tweet in newTweets {
            let textNode = createTextNode(text: tweet.text, position: tweet.worldPosition)
            textNode.name = "nearby_tweet_\(tweet.id)"
            
            // All tweets use the same green iMessage style with white text
            // No color variations needed - consistent design throughout
            
            sceneView.scene.rootNode.addChildNode(textNode)
        }
        
        nearbyTweets = filteredTweets
        
        // Update mini-map with nearby tweets
        miniMapView?.updateNearbyTweets(filteredTweets)
        
        // Debug info
        if newTweets.count > 0 {
            print("✨ Rendered \(newTweets.count) new nearby tweets (total rendered: \(renderedNearbyTweetIds.count))")
        }
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
        firebaseService.fetchNearbyTweets(location: searchLocation, radius: cappedRadius) { [weak self] tweets, error in
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
            let textNode = createTextNode(text: tweet.text, position: tweet.worldPosition)
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
    
    func createTextNode(text: String, position: SCNVector3) -> SCNNode {
        // Create the text geometry
        let textGeometry = SCNText(string: text, extrusionDepth: 0.01)
        textGeometry.font = UIFont.systemFont(ofSize: 0.2, weight: .medium)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        textGeometry.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.3)
        
        // Create text node
        let textNode = SCNNode(geometry: textGeometry)
        
        // Center the text using proper pivot
        let (min, max) = textGeometry.boundingBox
        let dx = Float(max.x - min.x)
        let dy = Float(max.y - min.y)
        let dz = Float(max.z - min.z)
        
        // Set the pivot to center the text geometry
        textNode.pivot = SCNMatrix4MakeTranslation(dx/2, dy/2, dz/2)
        
        // Position the text at the specified world position
        textNode.position = position
        
        // Make the text face the camera
        textNode.constraints = [SCNBillboardConstraint()]
        
        // Add some animation
        textNode.scale = SCNVector3(0, 0, 0)
        let scaleAction = SCNAction.scale(to: 1.0, duration: 0.3)
        scaleAction.timingMode = .easeOut
        textNode.runAction(scaleAction)
        
        return textNode
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
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard isWaitingForTap, let tweetText = pendingTweetText else { return }
        
        let location = gesture.location(in: sceneView)
        createTweetAtLocation(text: tweetText, location: location)
        
        // Reset state
        isWaitingForTap = false
        pendingTweetText = nil
        
        // Reset button
        button.setTitle("Enter", for: .normal)
        button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        button.setTitleColor(UIColor.white, for: .normal)
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
        let textNode = createTextNode(text: text, position: tweetPosition)
        textNode.name = "my_tweet_\(UUID().uuidString)"
        
        // Store reference to the tweet node and text
        tweetNodes.append(textNode)
        tweetTexts.append(text)
        
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
        let textNode = createTextNode(text: text, position: tweetPosition)
        textNode.name = "my_tweet_\(UUID().uuidString)"
        
        // Store reference to the tweet node and text
        tweetNodes.append(textNode)
        tweetTexts.append(text)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(textNode)
    }
    
    func savePersistentTweet(text: String, position: SCNVector3) {
        guard let userId = currentUserId,
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
            isPublic: true
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
        
        // Reload table view
        historyTableView.reloadData()
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tweetTexts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TweetCell", for: indexPath)
        cell.textLabel?.text = tweetTexts[indexPath.row]
        cell.textLabel?.textColor = UIColor.systemGreen
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
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
        
        return cell
    }
    
    @objc func deleteButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        deleteTweet(at: index)
    }
    
    // MARK: - UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        enterButtonTapped()
        return true
    }
    
    // MARK: - ARSCNViewDelegate
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
                    let newTextNode = createTextNode(text: tweetText, position: node.position)
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
}

