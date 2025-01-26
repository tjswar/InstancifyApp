import Foundation
import AWSCore
import AWSEC2

class AWSConfigurationService {
    static func configure() {
        print("🔧 AWSConfig: Setting up default configuration...")
        
        // Set default configuration with no credentials
        let configuration = AWSServiceConfiguration(
            region: .USEast1,
            credentialsProvider: nil
        )!
        
        // Set default service configuration
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        print("🔧 AWSConfig: Default configuration set")
    }
    
    static func updateConfiguration(
        accessKeyId: String,
        secretAccessKey: String,
        region: AWSRegionType
    ) {
        print("🔧 AWSConfig: Updating configuration...")
        print("🔧 AWSConfig: Region: \(region)")
        print("🔧 AWSConfig: Region string value: \(region.stringValue)")
        
        // Clean up existing configuration
        AWSServiceManager.default().defaultServiceConfiguration = nil
        AWSEC2.remove(forKey: "DefaultKey")
        AWSEC2.remove(forKey: "ValidationKey")
        
        // Create credentials provider
        let credentialsProvider = AWSStaticCredentialsProvider(
            accessKey: accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
            secretKey: secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        // Create endpoint
        let regionString = region.stringValue.lowercased()
        let serviceEndpoint = "ec2.\(regionString).amazonaws.com"
        let url = URL(string: "https://\(serviceEndpoint)")!
        
        print("🔧 AWSConfig: Using endpoint: \(serviceEndpoint)")
        
        let endpoint = AWSEndpoint(
            region: region,
            serviceName: "ec2",
            url: url
        )
        
        // Create and set configuration
        let configuration = AWSServiceConfiguration(
            region: region,
            endpoint: endpoint,
            credentialsProvider: credentialsProvider
        )!
        
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        print("🔧 AWSConfig: ✅ Configuration updated successfully")
    }
    
    private static func unregisterServices() {
        AWSEC2.remove(forKey: "DefaultKey")
    }
    
    private static func registerServices(with configuration: AWSServiceConfiguration) {
        AWSEC2.register(with: configuration, forKey: "DefaultKey")
    }
} 