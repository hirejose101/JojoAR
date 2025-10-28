//
//  PermissionViewController.swift
//  ARKitDraw
//
//  Created for Meden permissions onboarding
//

import UIKit
import AVFoundation
import CoreLocation

class PermissionViewController: UIViewController {
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Hey there!\n\nTo enjoy the full Meden experience, please allow access to your camera and location.\n\nYour camera lets you view AR posts in the world around you, and your location helps you discover the ones nearby"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .left
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Continue", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(continueButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    var onPermissionGranted: (() -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
    }
    
    private func setupUI() {
        // Set green background
        view.backgroundColor = UIColor(red: 0.0, green: 0.75, blue: 0.39, alpha: 1.0)
        
        // Create container for instruction label with padding
        let containerView = UIView()
        containerView.backgroundColor = .black
        containerView.layer.cornerRadius = 12
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        containerView.addSubview(instructionLabel)
        view.addSubview(continueButton)
        
        // Remove background from label since container has it
        instructionLabel.backgroundColor = .clear
        
        NSLayoutConstraint.activate([
            // Container view - centered with padding
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            
            // Instruction label inside container with padding (left aligned)
            instructionLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            instructionLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24),
            
            // Continue button - no container, just centered
            continueButton.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 40),
            continueButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            continueButton.widthAnchor.constraint(equalToConstant: 150),
            continueButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc private func continueButtonTapped() {
        // Request camera permission first
        requestCameraPermission()
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    // Camera granted, now request location
                    self?.requestLocationPermission()
                } else {
                    // Camera denied, still try to get location
                    self?.requestLocationPermission()
                }
            }
        }
    }
    
    private func requestLocationPermission() {
        let locationManager = CLLocationManager()
        locationManager.requestWhenInUseAuthorization()
        
        // Mark as not first launch
        UserDefaults.standard.set(true, forKey: "HasShownPermissionScreen")
        
        // Post notification to start location updates
        NotificationCenter.default.post(name: NSNotification.Name("StartLocationUpdates"), object: nil)
        
        // Dismiss and proceed to main app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.onPermissionGranted?()
            self?.dismiss(animated: true, completion: nil)
        }
    }
}

