//
//  AppDelegate.swift
//  CustomCamera
//
//  Created by Nicolás Miari on 2018/10/05.
//  Copyright © 2018 Nicolás Miari. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.orientationChanged(notification:)),
            name: UIDevice.orientationDidChangeNotification,
            object: nil)

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

    func getInitialOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let orientation : UIDeviceOrientation = UIDevice.current.orientation
        print("initial orientation: \(orientation.rawValue )")
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    @objc func orientationChanged(notification: NSNotification ){
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let orientation : UIDeviceOrientation = UIDevice.current.orientation
        let num : NSNumber = NSNumber(value: orientation.rawValue)
        let userDict : [String: NSNumber] = [ "orientation" : num ]
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "orientationWillChange"), object: self, userInfo: userDict)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
}

