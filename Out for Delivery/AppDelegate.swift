//
//  AppDelegate.swift
//  Out for Delivery
//
//  SwiftUI apps have no application delegate by default, but accepting a CloudKit
//  share invitation requires one: it points each new scene at our custom
//  SceneDelegate, which receives the accepted share. Wired up in the App via
//  @UIApplicationDelegateAdaptor.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
