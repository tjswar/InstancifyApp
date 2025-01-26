import SwiftUI

class AppLockService: ObservableObject {
    static let shared = AppLockService()
    
    @AppStorage("isAppLockEnabled") var isAppLockEnabled = false {
        didSet {
            if isAppLockEnabled {
                if storedPIN.isEmpty {
                    // Don't lock if PIN isn't set
                    isAppLockEnabled = false
                } else {
                    lastUnlockTime = Date()
                    isLocked = true
                }
            } else {
                isLocked = false
                lastUnlockTime = Date()
            }
        }
    }
    
    @AppStorage("appLockTimeout") var appLockTimeout: Double = 0
    @Published var isLocked = false
    
    @AppStorage("appLockPIN") var storedPIN: String = ""
    @Published var isUnlocked = false
    
    private var lastUnlockTime = Date()
    private var backgroundDate: Date?
    
    private init() {
        // Only start locked if PIN is set and lock is enabled
        if isAppLockEnabled && !storedPIN.isEmpty {
            isLocked = true
        } else {
            isLocked = false
            isAppLockEnabled = false
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        if isAppLockEnabled && !storedPIN.isEmpty {
            backgroundDate = Date()
            isLocked = true
        }
    }
    
    @objc private func appWillEnterForeground() {
        checkLockState()
    }
    
    func checkLockState() {
        guard isAppLockEnabled && !storedPIN.isEmpty else {
            isLocked = false
            return
        }
        
        if let backgroundDate = backgroundDate {
            let timeInBackground = Date().timeIntervalSince(backgroundDate)
            if timeInBackground >= appLockTimeout {
                isLocked = true
            }
        } else {
            let timeSinceLastUnlock = Date().timeIntervalSince(lastUnlockTime)
            if timeSinceLastUnlock >= appLockTimeout {
                isLocked = true
            }
        }
    }
    
    func setPIN(_ pin: String) {
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else { return }
        storedPIN = pin
    }
    
    func removePIN() {
        storedPIN = ""
        isAppLockEnabled = false
        isLocked = false
    }
    
    func authenticate() async throws {
        // Show PIN dialog
        await MainActor.run {
            isUnlocked = false
            showPINPrompt()
        }
    }
    
    @MainActor
    private func showPINPrompt() {
        let alert = UIAlertController(
            title: "Enter PIN",
            message: "Enter your 4-digit PIN to unlock Instancify",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = "PIN"
            textField.keyboardType = .numberPad
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Unlock", style: .default) { [weak self] _ in
            guard let pin = alert.textFields?.first?.text,
                  pin == self?.storedPIN else {
                self?.showError()
                return
            }
            self?.isUnlocked = true
            self?.unlock()
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let viewController = windowScene.windows.first?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }
    
    @MainActor
    private func showError() {
        let alert = UIAlertController(
            title: "Error",
            message: "Incorrect PIN. Please try again.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.showPINPrompt()
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let viewController = windowScene.windows.first?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }
    
    func lock() {
        isUnlocked = false
        isLocked = true
    }
    
    func unlock() {
        isLocked = false
        isUnlocked = true
        lastUnlockTime = Date()
        backgroundDate = nil
    }
} 