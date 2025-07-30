import UIKit
import MapKit
import CoreLocation

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
        mapView.showsPointsOfInterest = false
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
        // Remove existing tweet annotations
        for annotation in tweetAnnotations.values {
            mapView.removeAnnotation(annotation)
        }
        tweetAnnotations.removeAll()
        
        // Add new tweet annotations (blue)
        for tweet in tweets {
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: tweet.latitude, longitude: tweet.longitude)
            annotation.title = tweet.text
            mapView.addAnnotation(annotation)
            tweetAnnotations[tweet.id] = annotation
        }
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
        
        // Set different colors for user vs tweets
        if annotation.title == "You" {
            // User location - green circle
            annotationView?.image = createCircleImage(size: 12, color: UIColor.green)
        } else {
            // Tweet location - blue circle
            annotationView?.image = createCircleImage(size: 8, color: UIColor.blue)
        }
        
        return annotationView
    }
    
    private func createCircleImage(size: CGFloat, color: UIColor) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)
        
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(color.cgColor)
        context?.fillEllipse(in: rect)
        
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
        fullScreenMapView?.showsPointsOfInterest = false
        fullScreenMapView?.delegate = self
        
        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        closeButton.setTitleColor(UIColor.white, for: .normal)
        closeButton.backgroundColor = UIColor.red.withAlphaComponent(0.8)
        closeButton.layer.cornerRadius = 20
        closeButton.frame = CGRect(x: superview.bounds.width - 60, y: 120, width: 40, height: 40)
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
        
        // Animate in
        UIView.animate(withDuration: 0.3) {
            self.fullScreenContainer?.alpha = 1
        }
        
        isFullScreen = true
    }
    
    @objc private func hideFullScreenMap() {
        UIView.animate(withDuration: 0.3, animations: {
            self.fullScreenContainer?.alpha = 0
        }) { _ in
            self.fullScreenContainer?.removeFromSuperview()
            self.fullScreenContainer = nil
            self.fullScreenMapView = nil
            self.isFullScreen = false
        }
    }
} 