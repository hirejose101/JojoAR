//
//  AppDelegate.swift
//  ARKitDraw
//
//  Created by Felix Lapalme on 2017-06-07.
//  Copyright © 2017 Felix Lapalme. All rights reserved.
//

import UIKit
import Firebase

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Check if this is the first launch and show permission screen BEFORE ViewController loads
        let hasShownPermissionScreen = UserDefaults.standard.bool(forKey: "HasShownPermissionScreen")
        
        if !hasShownPermissionScreen {
            // Show permission screen immediately after a brief delay to let window setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showPermissionScreen()
            }
        }
        
        // Override point for customization after application launch.
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    private func showPermissionScreen() {
        guard let window = self.window,
              let rootViewController = window.rootViewController else {
            return
        }
        
        // Only show if not already presented
        if rootViewController.presentedViewController == nil {
            let permissionVC = PermissionViewController()
            permissionVC.onPermissionGranted = {
                // Permissions granted and screen will dismiss
            }
            
            permissionVC.modalPresentationStyle = UIModalPresentationStyle.fullScreen
            rootViewController.present(permissionVC, animated: true, completion: nil)
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

