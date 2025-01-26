import SwiftUI

struct LockScreenView: View {
    @StateObject private var appLockService = AppLockService.shared
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    appearanceViewModel.currentAccentColor.opacity(0.8),
                    appearanceViewModel.currentAccentColor.opacity(0.2)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Blur effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Lock icon with glow effect
                ZStack {
                    Circle()
                        .fill(appearanceViewModel.currentAccentColor.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: isAnimating ? 20 : 10)
                    
                    Circle()
                        .stroke(appearanceViewModel.currentAccentColor.opacity(0.5), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color.white)
                        .shadow(color: appearanceViewModel.currentAccentColor.opacity(0.5), radius: 8)
                }
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                .onAppear { isAnimating = true }
                
                VStack(spacing: 16) {
                    Text("App Locked")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.primary)
                    
                    Text("Enter your PIN to unlock Instancify")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button {
                    Task {
                        do {
                            try await appLockService.authenticate()
                            if appLockService.isUnlocked {
                                appLockService.unlock()
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "number.square.fill")
                            .font(.system(size: 20))
                        Text("Enter PIN")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(appearanceViewModel.currentAccentColor)
                            .shadow(color: appearanceViewModel.currentAccentColor.opacity(0.5), radius: 8, y: 4)
                    )
                    .padding(.horizontal, 32)
                }
            }
            .padding(32)
        }
        .alert("Authentication Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
} 