import Foundation
import CoreLocation
import Combine

class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()
    
    struct WeatherData {
        let temperature: Double // °C
        let humidity: Double // %
        let airQualityIndex: Int // AQI
        let pollenLevel: String // "Low", "Moderate", "High", "Very High"
        let condition: String // "Sunny", "Cloudy", "Rainy", "Windy"
        let iconName: String // SF Symbol
    }
    
    @Published var currentWeatherData: WeatherData?
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastFetchTime: Date?
    private let fetchCooldown: TimeInterval = 600 // 10 minutes cache cooldown
    
    private var cachedWeatherData: WeatherData
    
    private static func getMockWeather() -> WeatherData {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        let hour = calendar.component(.hour, from: Date())
        
        let baseTemp: Double
        let pollen: String
        let aqi: Int
        let condition: String
        let icon: String
        
        switch month {
        case 3...5: // Spring
            baseTemp = 15.0
            pollen = "High"
            aqi = 78
            condition = "Windy"
            icon = "wind"
        case 6...8: // Summer
            baseTemp = 26.0
            pollen = "Moderate"
            aqi = 48
            condition = "Sunny"
            icon = "sun.max.fill"
        case 9...11: // Autumn
            baseTemp = 12.0
            pollen = "Moderate"
            aqi = 52
            condition = "Cloudy"
            icon = "cloud.fill"
        default: // Winter
            baseTemp = 4.0
            pollen = "Low"
            aqi = 35
            condition = "Rainy"
            icon = "cloud.rain.fill"
        }
        
        // Diurnal temperature variation (warmer in afternoon, cooler at night)
        let hourFactor = sin(Double(hour - 6) * Double.pi / 12.0) // ranges from -1 to 1
        let temperature = baseTemp + hourFactor * 4.0
        let humidity = 60.0 - hourFactor * 15.0 // humidity drops when temp rises
        
        return WeatherData(
            temperature: round(temperature * 10) / 10,
            humidity: round(humidity * 10) / 10,
            airQualityIndex: aqi,
            pollenLevel: pollen,
            condition: condition,
            iconName: icon
        )
    }
    
    override private init() {
        self.cachedWeatherData = Self.getMockWeather()
        super.init()
        self.currentWeatherData = self.cachedWeatherData
        
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        
        // Check authorization and start updating
        DispatchQueue.main.async {
            self.checkLocationAuthorization()
        }
    }
    
    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("WeatherManager: Location access denied/restricted. Falling back to mock weather.")
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Check if we need to fetch weather (e.g. if we moved more than 2km, or if cooldown expired)
        let shouldFetch: Bool
        if let lastLoc = lastLocation {
            let distance = location.distance(from: lastLoc)
            let timeElapsed = Date().timeIntervalSince(lastFetchTime ?? .distantPast)
            shouldFetch = distance > 2000 || timeElapsed > fetchCooldown
        } else {
            shouldFetch = true
        }
        
        if shouldFetch {
            lastLocation = location
            lastFetchTime = Date()
            fetchWeatherAndAirQuality(for: location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("WeatherManager: Location manager failed with error: \(error.localizedDescription)")
    }
    
    private func fetchWeatherAndAirQuality(for location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        let weatherURLString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code"
        let aqURLString = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(lat)&longitude=\(lon)&current=us_aqi,birch_pollen,grass_pollen,ragweed_pollen"
        
        guard let weatherURL = URL(string: weatherURLString),
              let aqURL = URL(string: aqURLString) else {
            return
        }
        
        let group = DispatchGroup()
        var temp: Double?
        var hum: Double?
        var weatherCode: Int?
        var aqi: Int?
        var maxPollen: Double?
        
        // Fetch Weather
        group.enter()
        URLSession.shared.dataTask(with: weatherURL) { data, response, error in
            defer { group.leave() }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any] {
                temp = current["temperature_2m"] as? Double
                hum = current["relative_humidity_2m"] as? Double
                weatherCode = current["weather_code"] as? Int
            }
        }.resume()
        
        // Fetch Air Quality / Pollen
        group.enter()
        URLSession.shared.dataTask(with: aqURL) { data, response, error in
            defer { group.leave() }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any] {
                if let usAqi = current["us_aqi"] as? Double {
                    aqi = Int(usAqi)
                } else if let usAqiInt = current["us_aqi"] as? Int {
                    aqi = usAqiInt
                }
                
                let birch = current["birch_pollen"] as? Double ?? 0.0
                let grass = current["grass_pollen"] as? Double ?? 0.0
                let ragweed = current["ragweed_pollen"] as? Double ?? 0.0
                maxPollen = max(birch, max(grass, ragweed))
            }
        }.resume()
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Map weather code to text and icon
            let code = weatherCode ?? 0
            let mappedCondition = self.mapWeatherCodeToCondition(code)
            let mappedIcon = self.mapWeatherCodeToIcon(code)
            
            // Map pollen count to levels
            let pollenVal = maxPollen ?? 0.0
            let mappedPollen: String
            if pollenVal < 10.0 {
                mappedPollen = "Low"
            } else if pollenVal < 50.0 {
                mappedPollen = "Moderate"
            } else if pollenVal < 150.0 {
                mappedPollen = "High"
            } else {
                mappedPollen = "Very High"
            }
            
            let updatedWeather = WeatherData(
                temperature: temp ?? self.cachedWeatherData.temperature,
                humidity: hum ?? self.cachedWeatherData.humidity,
                airQualityIndex: aqi ?? self.cachedWeatherData.airQualityIndex,
                pollenLevel: mappedPollen,
                condition: mappedCondition,
                iconName: mappedIcon
            )
            
            self.cachedWeatherData = updatedWeather
            self.currentWeatherData = updatedWeather
            print("WeatherManager: Successfully updated weather with live API data: \(updatedWeather)")
        }
    }
    
    private func mapWeatherCodeToCondition(_ code: Int) -> String {
        switch code {
        case 0:
            return "Sunny"
        case 1, 2, 3:
            return "Cloudy"
        case 45, 48:
            return "Foggy"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return "Rainy"
        case 71, 73, 75, 77, 85, 86:
            return "Snowy"
        case 95, 96, 99:
            return "Windy"
        default:
            return "Sunny"
        }
    }
    
    private func mapWeatherCodeToIcon(_ code: Int) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1, 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55:
            return "cloud.drizzle.fill"
        case 56, 57, 61, 63, 65, 66, 67:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "snowflake"
        case 80, 81, 82:
            return "cloud.heavyrain.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "sun.max.fill"
        }
    }
    
    func getCurrentWeather() -> WeatherData {
        return cachedWeatherData
    }
}
