import CoreLocation
import Foundation
import MapKit

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLocating = false
    @Published var errorMessage: String?

    private let clManager = CLLocationManager()
    private var onAddress: ((String) -> Void)?

    private static let deniedMessage = "Location access denied. Please enable it in Settings."
    private static let lookupFailedMessage = "Could not determine location. Please enter the address manually."

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
            errorMessage = Self.deniedMessage
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
            errorMessage = Self.deniedMessage
            isLocating = false
            onAddress = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }

        // CLGeocoder was deprecated in iOS 26; MKReverseGeocodingRequest is the
        // MapKit replacement. `isLocating` stays true until the lookup finishes,
        // so the button keeps spinning for the whole round trip rather than
        // going idle while the address is still on its way.
        Task { [weak self] in
            guard let request = MKReverseGeocodingRequest(location: location) else {
                self?.finish(withError: Self.lookupFailedMessage)
                return
            }

            do {
                let mapItems = try await request.mapItems
                guard let address = mapItems.compactMap(Self.singleLineAddress(for:)).first else {
                    self?.finish(withError: Self.lookupFailedMessage)
                    return
                }
                self?.deliver(address)
            } catch {
                self?.finish(withError: Self.lookupFailedMessage)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(withError: Self.lookupFailedMessage)
    }

    // MARK: - Helpers

    /// The single-line postal address the Site Address field expects, e.g.
    /// "12 High Street, Manchester M1 2AB". The country is left off, matching
    /// what the old placemark-component formatting produced.
    private static func singleLineAddress(for mapItem: MKMapItem) -> String? {
        if let address = mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true),
           !address.isEmpty {
            return address
        }
        // Fall back to the full address, which does include the country.
        if let fullAddress = mapItem.address?.fullAddress, !fullAddress.isEmpty {
            return fullAddress
        }
        return nil
    }

    private func deliver(_ address: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLocating = false
            self.onAddress?(address)
            self.onAddress = nil
        }
    }

    private func finish(withError message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLocating = false
            self.errorMessage = message
            self.onAddress = nil
        }
    }
}
