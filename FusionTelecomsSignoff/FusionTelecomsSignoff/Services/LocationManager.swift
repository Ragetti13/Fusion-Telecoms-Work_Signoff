import CoreLocation
import Foundation

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLocating = false
    @Published var errorMessage: String?

    private let clManager = CLLocationManager()
    private var onAddress: ((String) -> Void)?

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetchAddress(completion: @escaping (String) -> Void) {
        onAddress = completion
        errorMessage = nil

        switch clManager.authorizationStatus {
        case .notDetermined:
            clManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isLocating = true
            clManager.requestLocation()
        default:
            errorMessage = "Location access denied. Please enable it in Settings."
            onAddress = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if onAddress != nil {
                isLocating = true
                manager.requestLocation()
            }
        case .denied, .restricted:
            errorMessage = "Location access denied. Please enable it in Settings."
            isLocating = false
            onAddress = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        isLocating = false
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self = self, let p = placemarks?.first else { return }
                let parts: [String?] = [
                    p.subThoroughfare, p.thoroughfare,
                    p.locality, p.administrativeArea, p.postalCode
                ]
                let address = parts.compactMap { $0 }.joined(separator: ", ")
                self.onAddress?(address)
                self.onAddress = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        errorMessage = "Could not determine location. Please enter the address manually."
        onAddress = nil
    }
}
