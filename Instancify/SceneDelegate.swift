import UIKit
import SwiftUI
import BackgroundTasks

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)
        let contentView = ContentView()
            .environmentObject(AuthenticationManager.shared)
            .environmentObject(NotificationManager.shared)
            .environmentObject(EC2Service.shared)
            .environmentObject(AppearanceSettingsViewModel.shared)
            .environmentObject(AppLockService.shared)
        
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        
        // Register for background tasks
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.instancify.autostop",
            using: nil
        ) { task in
            Task { @MainActor in
                AutoStopService.shared.processBackgroundTask(task as! BGProcessingTask)
            }
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called when scene is disconnected
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { @MainActor in
            await AuthenticationManager.shared.handleAppActivation()
            // Check app lock state when becoming active
            if AppLockService.shared.isAppLockEnabled {
                AppLockService.shared.checkLockState()
            }
        }
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        Task { @MainActor in
            AuthenticationManager.shared.didEnterBackground()
            // Lock app when resigning active if enabled
            if AppLockService.shared.isAppLockEnabled {
                AppLockService.shared.lock()
            }
        }
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        AuthenticationManager.shared.didEnterBackground()
        // Ensure app is locked when entering background if enabled
        if AppLockService.shared.isAppLockEnabled {
            AppLockService.shared.lock()
        }
    }
} 