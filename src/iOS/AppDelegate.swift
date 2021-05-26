//
//  AppDelegate.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit
import UserNotifications

@objcMembers
class AppDelegate: UIResponder, UIApplicationDelegate {
    class var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
    var window: UIWindow?
    weak var mapView: MapView!
    var userName: String?
    var userPassword: String?
    private(set) var isAppUpgrade = false
    var externalGPS: ExternalGPS?

	override init() {
		super.init()

		// do translations from old Obj-C names to Swift names
		NSKeyedUnarchiver.setClass(PresetKeyUserDefined.classForKeyedArchiver(), 	forClassName: "CustomPreset")
		NSKeyedUnarchiver.setClass(PresetValue.classForKeyedArchiver(), 		 	forClassName: "PresetValue")
		NSKeyedUnarchiver.setClass(QuadMap.classForKeyedArchiver(), 				forClassName: "QuadMap")
		NSKeyedUnarchiver.setClass(MyUndoManager.classForKeyedArchiver(), 			forClassName: "UndoManager")
		NSKeyedUnarchiver.setClass(OsmMapData.classForKeyedArchiver(), 				forClassName: "OsmMapData")
	}

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let url = launchOptions?[.url] as? URL
        if let url = url {
            if !url.isFileURL {
                return false
            }
            if url.pathExtension != "gpx" {
                return false
            }
        }
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		#if false
		// This code sets the screen size as mandated for Mac App Store screen shots
		let setScreenSizeForAppStoreScreenShots = false
		if setScreenSizeForAppStoreScreenShots {
			let size = CGSize( 640 * (1440.0/752) * (1440.0/1337) * (1440.0/1431), 640 * (900.0/752) * (900.0/877) * (900.0/898) + 1 )
			for scene in UIApplication.sharedApplication.connectedScenes {
				scene.sizeRestrictions.minimumSize = size;
				scene.sizeRestrictions.maximumSize = size;
			}
		}
		#endif

		let defaults: UserDefaults = UserDefaults.standard

        // save the app version so we can detect upgrades
        let prevVersion = defaults.object(forKey: "appVersion") as? String
        if prevVersion != appVersion() {
            print("Upgrade!")
            isAppUpgrade = true
        }
        defaults.set(appVersion(), forKey: "appVersion")

        // read name/password from keychain
        userName = KeyChain.getStringForIdentifier("username")
        userPassword = KeyChain.getStringForIdentifier("password")

        removePlaintextCredentialsFromUserDefaults()

        // self.externalGPS = [[ExternalGPS alloc] init];

        let url = launchOptions?[.url] as? URL
        if let url = url {
            // somebody handed us a URL to open
            return self.application(application, open: url, options: [:])
        }

        return true
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            let url = userActivity.webpageURL
            if let url = url {
                return self.application(application, open: url, options: [:])
            }
        }
        return false
    }

    /// Makes sure that the user defaults do not contain plaintext credentials from previous app versions.
    func removePlaintextCredentialsFromUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "password")
    }

    func setMapLocation(_ location: MapLocation?) {
        let delayInSeconds = 0.1
        let popTime = DispatchTime.now() + Double(Int64(delayInSeconds * Double(NSEC_PER_SEC)))
        DispatchQueue.main.asyncAfter(deadline: popTime, execute: { [self] in
            mapView?.setMapLocation(location)
        })
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if url.isFileURL && (url.pathExtension == "gpx") {
            // Load GPX
            _=url.startAccessingSecurityScopedResource()
            let data: Data? = try? Data(contentsOf: url, options: [])
			url.stopAccessingSecurityScopedResource()

            let delayInSeconds = 1.0
            let popTime = DispatchTime.now() + Double(Int64(delayInSeconds * Double(NSEC_PER_SEC)))
            DispatchQueue.main.asyncAfter(deadline: popTime, execute: { [self] in
                let ok = mapView?.gpxLayer.loadGPXData(data ?? Data(), center: true) ?? false
                if !ok {
                    let alert = UIAlertController(
                        title: NSLocalizedString("Open URL", comment: ""),
                        message: NSLocalizedString("Sorry, an error occurred while loading the GPX file", comment: ""),
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                    mapView?.mainViewController.present(alert, animated: true)
                }
            })
            return true
        } else if url.absoluteString.count > 0 {
            // geo: and gomaposm: support
            let urlParser = LocationURLParser()
            let parserResult = urlParser.parseURL(url)
            if let parserResult = parserResult {
                let delayInSeconds = 1.0
                let popTime = DispatchTime.now() + Double(Int64(delayInSeconds * Double(NSEC_PER_SEC)))
                DispatchQueue.main.asyncAfter(deadline: popTime, execute: { [self] in
                    setMapLocation(parserResult)
                })
                return true
            } else {
                let alertView = UIAlertController(title: NSLocalizedString("Invalid URL", comment: ""), message: url.absoluteString, preferredStyle: .alert)
                alertView.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                mapView?.mainViewController.present(alertView, animated: true)
                return false
            }
        }
        return false
    }

    func appName() -> String {
        return Bundle.main.infoDictionary?["CFBundleDisplayName"] as! String
    }

    func appVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
    }

    func appBuildNumber() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as! String
	}

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // set app badge if edits are pending
        let pendingEdits = mapView?.editorLayer.mapData.modificationCount() ?? 0
        if pendingEdits != 0 {
            UNUserNotificationCenter.current().requestAuthorization(options: .badge, completionHandler: { granted, error in
            })
        }
        UIApplication.shared.applicationIconBadgeNumber = pendingEdits

        // while in background don't update our location so we don't download tiles/OSM data when moving
        mapView?.userOverrodeLocationPosition = true
        mapView?.locationManager.stopUpdatingHeading()
    }

    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    func applicationWillEnterForeground(_ application: UIApplication) {
        // allow gps to update our location
        mapView?.userOverrodeLocationPosition = false
        if mapView?.gpsState != GPS_STATE_NONE {
            mapView?.locationManager.startUpdatingHeading()
        }

        // remove badge now, so it disappears promptly on exit
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    class func askUser(toAllowLocationAccess parentVC: UIViewController?) {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let title = String.localizedStringWithFormat(NSLocalizedString("Turn On Location Services to Allow %@ to Determine Your Location", comment: ""), appName ?? "")

        AppDelegate.askUserToOpenSettings(withAlertTitle: title, message: nil, parentVC: parentVC)
    }

    class func askUserToOpenSettings(withAlertTitle title: String?, message: String?, parentVC: UIViewController?) {
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert)
        let okayAction = UIAlertAction(
            title: NSLocalizedString("OK", comment: ""),
            style: .cancel,
            handler: nil)
        let openSettings = UIAlertAction(
            title: NSLocalizedString("Open Settings", comment: "Open the iOS Settings app"),
            style: .default,
            handler: { action in
                AppDelegate.openAppSettings()
            })

        alertController.addAction(openSettings)
        alertController.addAction(okayAction)

        parentVC?.present(alertController, animated: true)
    }

    class func openAppSettings() {
        let openSettingsURL = URL(string: UIApplication.openSettingsURLString)
        if let openSettingsURL = openSettingsURL {
            UIApplication.shared.open(openSettingsURL, options: [:], completionHandler: nil)
        }
    }
}

//#import "MainViewController.h"