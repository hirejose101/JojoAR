import UIKit
import MapKit
import CoreLocation

// Protocol for search communication
protocol MiniMapSearchDelegate: AnyObject {
    func searchForTweetsInArea(center: CLLocationCoordinate2D, visibleRegion: MKCoordinateRegion)
}

class MiniMapView: UIView {
    
    // MARK: - Properties
    private let mapView = MKMapView()
    private let containerView = UIView()
    private let radius: CGFloat = 80 // Size of the circular map
    private var userAnnotation: MKPointAnnotation?
    private var tweetAnnotations: [String: MKPointAnnotation] = [:]
    
    // Full-screen map properties
    private var fullScreenMapView: MKMapView?
    private var fullScreenContainer: UIView?
    private var isFullScreen = false
    
    // Add properties for search functionality
    private var originalUserLocation: CLLocationCoordinate2D?
    private var searchButton: UIButton?
    private var searchInProgress = false
    private var searchDelegate: MiniMapSearchDelegate?
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMiniMap()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMiniMap()
    }
    
    // MARK: - Setup
    private func setupMiniMap() {
        // Configure container view
        containerView.frame = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        containerView.layer.cornerRadius = radius
        containerView.layer.borderWidth = 2
        containerView.layer.borderColor = UIColor.white.cgColor
        containerView.clipsToBounds = true
        addSubview(containerView)
        
        // Add tap gesture to expand map
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap))
        containerView.addGestureRecognizer(tapGesture)
        containerView.isUserInteractionEnabled = true
        
        // Configure map view
        mapView.frame = containerView.bounds
        mapView.layer.cornerRadius = radius
        mapView.clipsToBounds = true
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsUserLocation = false // We'll handle user location manually
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.showsBuildings = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.delegate = self  // THIS IS CRITICAL - enables viewFor method to work
        containerView.addSubview(mapView)
        
        // Set initial region (will be updated when location is available)
        let initialRegion = MKCoordinateRegionMakeWithDistance(
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            200, // 200 meter radius
            200
        )
        mapView.setRegion(initialRegion, animated: false)
    }
    
    // MARK: - Public Methods
    func updateUserLocation(_ location: CLLocation) {
        let coordinate = location.coordinate
        
        // Store original location for distance calculations
        if originalUserLocation == nil {
            originalUserLocation = coordinate
        }
        
        // Remove existing user annotation
        if let existingAnnotation = userAnnotation {
            mapView.removeAnnotation(existingAnnotation)
        }
        
        // Create new user annotation (green)
        userAnnotation = MKPointAnnotation()
        userAnnotation?.coordinate = coordinate
        userAnnotation?.title = "You"
        mapView.addAnnotation(userAnnotation!)
        
        // Center map on user location
        let region = MKCoordinateRegionMakeWithDistance(
            coordinate,
            200,
            200
        )
        mapView.setRegion(region, animated: true)
    }
    
    func updateNearbyTweets(_ tweets: [PersistentTweet]) {
        print("🗺️ MiniMapView: updateNearbyTweets called with \(tweets.count) tweets")
        
        // Remove existing tweet annotations
        for annotation in tweetAnnotations.values {
            mapView.removeAnnotation(annotation)
        }
        tweetAnnotations.removeAll()
        
        print("🗺️ MiniMapView: Cleared existing annotations")
        
        // Add new tweet annotations (blue dots only - no text to preserve AR discovery)
        for (index, tweet) in tweets.enumerated() {
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: tweet.latitude, longitude: tweet.longitude)
            annotation.title = "Tweet" // Set title so viewFor can identify it
            mapView.addAnnotation(annotation)
            tweetAnnotations[tweet.id] = annotation
            
            print("🗺️ MiniMapView: Added annotation \(index + 1) for tweet '\(tweet.text)' at \(tweet.latitude), \(tweet.longitude)")
        }
        
        print("🗺️ MiniMapView: Total annotations on mini-map: \(mapView.annotations.count)")
        
        // Also update full-screen map if it's open
        if isFullScreen, let fullScreenMap = fullScreenMapView {
            print("🗺️ MiniMapView: Updating full-screen map with \(tweets.count) tweets")
            
            // Remove existing tweet annotations from full-screen map
            for annotation in fullScreenMap.annotations {
                if let title = annotation.title, title != "You" {
                    fullScreenMap.removeAnnotation(annotation)
                }
            }
            
            // Add new tweet annotations to full-screen map (also no text - just circles)
            for tweet in tweets {
                let annotation = MKPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: tweet.latitude, longitude: tweet.longitude)
                annotation.title = "Tweet" // No tweet text - just circles
                fullScreenMap.addAnnotation(annotation)
                print("🗺️ MiniMapView: Added annotation to full-screen map for tweet '\(tweet.text)'")
            }
            
            print("🗺️ MiniMapView: Total annotations on full-screen map: \(fullScreenMap.annotations.count)")
        }
    }
    
    func setSearchDelegate(_ delegate: MiniMapSearchDelegate) {
        searchDelegate = delegate
    }
    
    func clearTweets() {
        for annotation in tweetAnnotations.values {
            mapView.removeAnnotation(annotation)
        }
        tweetAnnotations.removeAll()
    }
}

// MARK: - MKMapViewDelegate
extension MiniMapView: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip if it's the user location annotation (we handle it manually)
        if annotation is MKUserLocation {
            return nil
        }
        
        let identifier = "MiniMapAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        }
        
        // Configure annotation view
        annotationView?.annotation = annotation
        
        // Hide text labels - only show custom images
        annotationView?.canShowCallout = false        
        // Set different pins for user vs tweets
        if annotation.title == "You" {
            // User location - white pin
            annotationView?.image = createPinImage(size: 20, color: UIColor.white)
        } else {
            // Tweet location - neon green pin (using bright neon green instead of dark green)
            let neonGreenColor = UIColor(red: 0.0, green: 0.75, blue: 0.39, alpha: 1.0) // Bright neon green #00bf63
            annotationView?.image = createPinImage(size: 20, color: neonGreenColor)
        }
        
        return annotationView
    }
    
    private func createPinImage(size: CGFloat, color: UIColor) -> UIImage {
        let pinSize = size
        let rect = CGRect(x: 0, y: 0, width: pinSize, height: pinSize)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)
        
        let context = UIGraphicsGetCurrentContext()
        
        // Draw pin shape (circle with a point at bottom)
        let circleRect = CGRect(x: 2, y: 2, width: pinSize - 4, height: pinSize - 8)
        let pointRect = CGRect(x: pinSize/2 - 2, y: pinSize - 6, width: 4, height: 6)
        
        // Draw main circle
        context?.setFillColor(color.cgColor)
        context?.fillEllipse(in: circleRect)
        
        // Draw point at bottom
        context?.fillEllipse(in: pointRect)
        
        // Add black border for contrast
        context?.setStrokeColor(UIColor.black.cgColor)
        context?.setLineWidth(1)
        context?.strokeEllipse(in: circleRect)
        context?.strokeEllipse(in: pointRect)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image ?? UIImage()
    }
    
    // MARK: - Full Screen Map
    
    @objc private func handleMapTap() {
        if isFullScreen {
            hideFullScreenMap()
        } else {
            showFullScreenMap()
        }
    }
    
    private func showFullScreenMap() {
        guard let superview = self.superview else { return }
        
        // Create full-screen container
        fullScreenContainer = UIView(frame: superview.bounds)
        fullScreenContainer?.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        fullScreenContainer?.alpha = 0
        
        // Create full-screen map
        fullScreenMapView = MKMapView(frame: CGRect(x: 20, y: 100, width: superview.bounds.width - 40, height: superview.bounds.height - 200))
        fullScreenMapView?.layer.cornerRadius = 15
        fullScreenMapView?.layer.borderWidth = 3
        fullScreenMapView?.layer.borderColor = UIColor.white.cgColor
        fullScreenMapView?.clipsToBounds = true
        fullScreenMapView?.isScrollEnabled = true
        fullScreenMapView?.isZoomEnabled = true
        fullScreenMapView?.isRotateEnabled = false
        fullScreenMapView?.isPitchEnabled = false
        fullScreenMapView?.showsUserLocation = false
        fullScreenMapView?.showsCompass = true
        fullScreenMapView?.showsScale = true
        fullScreenMapView?.showsTraffic = false
        fullScreenMapView?.showsBuildings = false
        fullScreenMapView?.pointOfInterestFilter = .excludingAll
        fullScreenMapView?.delegate = self
        
        // Add close button - smaller and in corner
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        closeButton.setTitleColor(UIColor.white, for: .normal)
        closeButton.backgroundColor = UIColor(red: 0.0, green: 0.75, blue: 0.39, alpha: 0.9) // Mini map tweet green
        closeButton.layer.cornerRadius = 15
        closeButton.frame = CGRect(x: superview.bounds.width - 45, y: 95, width: 30, height: 30)
        closeButton.addTarget(self, action: #selector(hideFullScreenMap), for: .touchUpInside)
        
        // Add to superview
        superview.addSubview(fullScreenContainer!)
        fullScreenContainer?.addSubview(fullScreenMapView!)
        fullScreenContainer?.addSubview(closeButton)
        
        // Copy current annotations to full-screen map
        if let userAnnotation = userAnnotation {
            fullScreenMapView?.addAnnotation(userAnnotation)
        }
        for annotation in tweetAnnotations.values {
            fullScreenMapView?.addAnnotation(annotation)
        }
        
        // Set region to show all annotations
        if let userAnnotation = userAnnotation {
            let region = MKCoordinateRegionMakeWithDistance(
                userAnnotation.coordinate,
                500, // 500 meter radius for full screen
                500
            )
            fullScreenMapView?.setRegion(region, animated: false)
        }
        
        // Add search button (initially visible for testing, will be hidden when map moves)
        searchButton = UIButton(type: .system)
        searchButton?.setTitle("Search for posts in this area", for: .normal)
        searchButton?.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        searchButton?.setTitleColor(UIColor.black, for: .normal)
        searchButton?.backgroundColor = UIColor.white.withAlphaComponent(0.9) // White background with black text
        searchButton?.layer.cornerRadius = 20
        // Center the button horizontally and position it lower
        let screenWidth = superview.bounds.width
        let buttonWidth: CGFloat = 220
        let centerX = (screenWidth - buttonWidth) / 2
        searchButton?.frame = CGRect(x: centerX, y: 120, width: buttonWidth, height: 40) // Properly centered horizontally
        searchButton?.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)
        searchButton?.isHidden = false // Initially visible for testing
        searchButton?.layer.zPosition = 1000 // Ensure it's above the map
        searchButton?.layer.shadowColor = UIColor.black.cgColor // Black shadow for contrast
        searchButton?.layer.shadowOffset = CGSize(width: 0, height: 2)
        searchButton?.layer.shadowRadius = 4
        searchButton?.layer.shadowOpacity = 0.3
        fullScreenContainer?.addSubview(searchButton!)
        
        // Add map movement tracking
        fullScreenMapView?.addObserver(self, forKeyPath: "region", options: [.new], context: nil)
        
        // Animate in
        UIView.animate(withDuration: 0.3) {
            self.fullScreenContainer?.alpha = 1
        }
        
        isFullScreen = true
    }
    
    @objc private func searchButtonTapped() {
        guard let mapView = fullScreenMapView,
              !searchInProgress else { return }
        
        let center = mapView.centerCoordinate
        searchInProgress = true
        
        // Show loading state
        searchButton?.setTitle("Searching...", for: .normal)
        searchButton?.isEnabled = false
        
        // Get the visible region
        let visibleRegion = mapView.region
        
        // Call delegate to search for tweets
        searchDelegate?.searchForTweetsInArea(center: center, visibleRegion: visibleRegion)
        
        // Reset button after a delay (delegate will handle the actual search)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.searchButton?.setTitle("Search for posts in this area", for: .normal)
            self?.searchButton?.isEnabled = true
            self?.searchButton?.isUserInteractionEnabled = true
            self?.searchInProgress = false
        }
    }
    
    // Handle map movement to show/hide search button
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "region", let mapView = fullScreenMapView, let originalLocation = originalUserLocation {
            let currentCenter = mapView.centerCoordinate
            let distance = calculateDistance(from: originalLocation, to: currentCenter)
            
            print("🗺️ Map moved - Distance from original: \(Int(distance))m")
            
            // Show search button when moved beyond 200 meters
            let shouldShowButton = distance >= 200
            searchButton?.isHidden = !shouldShowButton
            
            print("🔍 Search button visibility: \(shouldShowButton ? "SHOWN" : "HIDDEN")")
        }
    }
    
    private func calculateDistance(from coord1: CLLocationCoordinate2D, to coord2: CLLocationCoordinate2D) -> CLLocationDistance {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }
    
    @objc private func hideFullScreenMap() {
        // Remove observer
        fullScreenMapView?.removeObserver(self, forKeyPath: "region")
        
        // Notify delegate to revert to original location tweets
        if let originalLocation = originalUserLocation {
            searchDelegate?.searchForTweetsInArea(center: originalLocation, visibleRegion: MKCoordinateRegion())
        }
        
        UIView.animate(withDuration: 0.3, animations: {
            self.fullScreenContainer?.alpha = 0
        }) { _ in
            self.fullScreenContainer?.removeFromSuperview()
            self.fullScreenContainer = nil
            self.fullScreenMapView = nil
            self.searchButton = nil
            self.isFullScreen = false
        }
    }
}