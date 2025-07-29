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

class ViewController: UIViewController, ARSCNViewDelegate, UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource {

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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Set text field delegate
        textField.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/world.scn")!
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Setup UI
        setupUI()
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
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
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    func setupUI() {
        // Configure text field
        textField.placeholder = "Enter your tweet..."
        textField.borderStyle = .roundedRect
        textField.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        textField.textColor = UIColor.black
        
        // Configure button
        button.setTitle("Enter", for: .normal)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(UIColor.white, for: .normal)
        button.layer.cornerRadius = 8
        
        // Add button action
        button.addTarget(self, action: #selector(enterButtonTapped), for: .touchUpInside)
        
        // Add tweet history button
        historyButton = UIButton(type: .system)
        historyButton.setTitle("📝", for: .normal)
        historyButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        historyButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        historyButton.setTitleColor(UIColor.white, for: .normal)
        historyButton.layer.cornerRadius = 25
        historyButton.layer.masksToBounds = true
        historyButton.translatesAutoresizingMaskIntoConstraints = false
        historyButton.addTarget(self, action: #selector(historyButtonTapped), for: .touchUpInside)
        view.addSubview(historyButton)
        
        // Position history button at top-left
        NSLayoutConstraint.activate([
            historyButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            historyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            historyButton.widthAnchor.constraint(equalToConstant: 50),
            historyButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Add history table view (initially hidden)
        historyTableView = UITableView()
        historyTableView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        historyTableView.layer.cornerRadius = 10
        historyTableView.layer.masksToBounds = true
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
        button.backgroundColor = UIColor.systemBlue
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
        
        // Create text geometry
        let textGeometry = SCNText(string: text, extrusionDepth: 0.1)
        textGeometry.font = UIFont.boldSystemFont(ofSize: 0.3)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        textGeometry.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.8)
        
        // Create text node
        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = tweetPosition
        
        // Center the text
        let (min, max) = textGeometry.boundingBox
        let dx = Float(max.x - min.x)
        let dy = Float(max.y - min.y)
        let dz = Float(max.z - min.z)
        textNode.pivot = SCNMatrix4MakeTranslation(dx/2, dy/2, dz/2)
        
        // Make text face the camera
        textNode.constraints = [SCNBillboardConstraint()]
        
        // Store reference to the tweet node and text
        tweetNodes.append(textNode)
        tweetTexts.append(text)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(textNode)
        
        // Add some animation
        textNode.scale = SCNVector3(0, 0, 0)
        let scaleAction = SCNAction.scale(to: 1.0, duration: 0.3)
        scaleAction.timingMode = .easeOut
        textNode.runAction(scaleAction)
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
        
        // Create text geometry
        let textGeometry = SCNText(string: text, extrusionDepth: 0.1)
        textGeometry.font = UIFont.boldSystemFont(ofSize: 0.3)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        textGeometry.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.8)
        
        // Create text node
        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = tweetPosition
        
        // Center the text
        let (min, max) = textGeometry.boundingBox
        let dx = Float(max.x - min.x)
        let dy = Float(max.y - min.y)
        let dz = Float(max.z - min.z)
        textNode.pivot = SCNMatrix4MakeTranslation(dx/2, dy/2, dz/2)
        
        // Make text face the camera
        textNode.constraints = [SCNBillboardConstraint()]
        
        // Store reference to the tweet node and text
        tweetNodes.append(textNode)
        tweetTexts.append(text)
        
        // Add to scene
        sceneView.scene.rootNode.addChildNode(textNode)
        
        // Add some animation
        textNode.scale = SCNVector3(0, 0, 0)
        let scaleAction = SCNAction.scale(to: 1.0, duration: 0.3)
        scaleAction.timingMode = .easeOut
        textNode.runAction(scaleAction)
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
        cell.textLabel?.textColor = UIColor.white
        cell.backgroundColor = UIColor.clear
        cell.selectionStyle = .none
        
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
}
