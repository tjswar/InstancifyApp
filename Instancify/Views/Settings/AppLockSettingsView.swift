import SwiftUI

struct AppLockSettingsView: View {
    @ObservedObject var appLockService: AppLockService
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var showPinSetup = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Form {
            Section {
                if appLockService.storedPIN.isEmpty {
                    Button("Set Up PIN") {
                        showPinSetup = true
                    }
                } else {
                    Toggle("Enable App Lock", isOn: $appLockService.isAppLockEnabled)
                    
                    Button("Change PIN", role: .none) {
                        showPinSetup = true
                    }
                    
                    Button("Remove PIN", role: .destructive) {
                        appLockService.removePIN()
                    }
                }
            } header: {
                Text("Security")
            } footer: {
                if appLockService.storedPIN.isEmpty {
                    Text("Set up a PIN to enable app lock")
                } else {
                    Text("When enabled, the app will be locked after the specified timeout period.")
                }
            }
            
            if appLockService.isAppLockEnabled {
                Section {
                    Picker("Lock After", selection: $appLockService.appLockTimeout) {
                        Text("Immediately").tag(0.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                        Text("15 minutes").tag(900.0)
                        Text("1 hour").tag(3600.0)
                    }
                } header: {
                    Text("Lock Timeout")
                }
            }
        }
        .navigationTitle("App Lock")
        .sheet(isPresented: $showPinSetup) {
            NavigationView {
                Form {
                    Section {
                        SecureField("Enter 4-digit PIN", text: $pin)
                            .keyboardType(.numberPad)
                        
                        SecureField("Confirm PIN", text: $confirmPin)
                            .keyboardType(.numberPad)
                    } header: {
                        Text(appLockService.storedPIN.isEmpty ? "Set PIN" : "Change PIN")
                    } footer: {
                        Text("PIN must be 4 digits")
                    }
                }
                .navigationTitle("PIN Setup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            pin = ""
                            confirmPin = ""
                            showPinSetup = false
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            savePin()
                        }
                        .disabled(pin.count != 4 || pin != confirmPin || !pin.allSatisfy { $0.isNumber })
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func savePin() {
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else {
            errorMessage = "PIN must be 4 digits"
            showError = true
            return
        }
        
        guard pin == confirmPin else {
            errorMessage = "PINs do not match"
            showError = true
            return
        }
        
        appLockService.setPIN(pin)
        pin = ""
        confirmPin = ""
        showPinSetup = false
    }
} 