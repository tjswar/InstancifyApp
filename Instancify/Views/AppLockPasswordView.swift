import SwiftUI

struct AppLockPasswordView: View {
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLockPassword") private var storedPassword: String = ""
    @AppStorage("useCustomPassword") private var useCustomPassword: Bool = false
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isChangingPassword = false
    @State private var currentPassword = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Use Custom Password", isOn: $useCustomPassword)
                        .onChange(of: useCustomPassword) { newValue in
                            if !newValue {
                                // Clear stored password when disabling
                                storedPassword = ""
                                password = ""
                                confirmPassword = ""
                            }
                        }
                } header: {
                    Text("Password Protection")
                } footer: {
                    Text("Enable to use a custom password instead of Face ID/Touch ID")
                }
                
                if useCustomPassword {
                    if storedPassword.isEmpty {
                        // Set New Password
                        Section {
                            SecureField("Enter Password", text: $password)
                                .textContentType(.newPassword)
                            
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                            
                            Toggle("Show Password", isOn: $showPassword)
                        } header: {
                            Text("Set Password")
                        } footer: {
                            Text("Password must be at least 4 characters")
                        }
                        
                        Section {
                            Button("Save Password") {
                                savePassword()
                            }
                            .disabled(password.count < 4 || password != confirmPassword)
                        }
                    } else {
                        // Change Password
                        Section {
                            if isChangingPassword {
                                SecureField("Current Password", text: $currentPassword)
                                    .textContentType(.password)
                                
                                SecureField("New Password", text: $password)
                                    .textContentType(.newPassword)
                                
                                SecureField("Confirm New Password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                
                                Toggle("Show Password", isOn: $showPassword)
                                
                                Button("Save New Password") {
                                    changePassword()
                                }
                                .disabled(currentPassword.isEmpty || password.count < 4 || password != confirmPassword)
                            } else {
                                Button("Change Password") {
                                    isChangingPassword = true
                                }
                            }
                            
                            Button("Remove Password", role: .destructive) {
                                removePassword()
                            }
                        } header: {
                            Text("Manage Password")
                        }
                    }
                }
            }
            .navigationTitle("App Lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func savePassword() {
        guard password.count >= 4 else {
            errorMessage = "Password must be at least 4 characters"
            showError = true
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        storedPassword = password
        password = ""
        confirmPassword = ""
    }
    
    private func changePassword() {
        guard currentPassword == storedPassword else {
            errorMessage = "Current password is incorrect"
            showError = true
            return
        }
        
        guard password.count >= 4 else {
            errorMessage = "Password must be at least 4 characters"
            showError = true
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        storedPassword = password
        password = ""
        confirmPassword = ""
        currentPassword = ""
        isChangingPassword = false
    }
    
    private func removePassword() {
        storedPassword = ""
        password = ""
        confirmPassword = ""
        currentPassword = ""
        isChangingPassword = false
    }
} 