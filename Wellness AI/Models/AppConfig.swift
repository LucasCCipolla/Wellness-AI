import Foundation

struct AppConfig {
    /// OpenAI API Key. 
    /// Loaded dynamically from Secrets.plist. For production, this should be 
    /// fetched from a secure backend or injected via environment variables.
    static var openAIKey: String {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let xml = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
              let apiKey = plist["OpenAIKey"] as? String else {
            // Safe fallback placeholder for public code
            return "YOUR_OPENAI_API_KEY"
        }
        return apiKey
    }
}
