import CoreLocation
import Foundation
import MapKit
import UserNotifications

/// On-site sign-off reminders: each open (unsigned) job's address becomes a
/// geofence, and arriving on site raises a local notification to get the job
/// signed off. Opt-in from Settings — background geofencing needs "Always"
/// location permission, which iOS grants in its own two-step flow.
///
/// Everything is on-device: addresses are geocoded locally, regions are
/// monitored by iOS (works even if the app isn't running), and the reminder
/// is a local notification. No server involvement.
final class SiteReminderManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SiteReminderManager()

    @Published private(set) var enabled: Bool
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let clManager = CLLocationManager()

    private static let enabledKey = "SiteRemindersEnabled"
    private static let coordinateCacheKey = "SiteReminderGeocodeCache"
    private static let lastNotifiedKey = "SiteReminderLastNotified"
    private static let regionPrefix = "site-reminder-"
    /// iOS caps an app at 20 monitored regions; leave headroom for safety.
    private static let maxRegions = 18
    private static let regionRadius: CLLocationDistance = 150
    /// Don't re-remind about the same job within this window (seconds).
    private static let renotifyInterval: TimeInterval = 4 * 60 * 60

    /// Job details the entry event needs, keyed by region identifier — kept in
    /// UserDefaults because the entry can wake the app from nothing.
    private struct RegionInfo: Codable {
        let customerName: String
        let jobReference: String
    }
    private static let regionInfoKey = "SiteReminderRegionInfo"

    private override init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        authorizationStatus = clManager.authorizationStatus
        super.init()
        clManager.delegate = self
    }

    /// Whether the permission we hold can actually deliver reminders.
    var hasAlwaysPermission: Bool { authorizationStatus == .authorizedAlways }

    func setEnabled(_ on: Bool, jobs: [WorkOrder]) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            // iOS grants Always in two steps: WhenInUse first, then the
            // upgrade prompt. Request whatever step is next.
            switch clManager.authorizationStatus {
            case .notDetermined:
                clManager.requestAlwaysAuthorization()
            case .authorizedWhenInUse:
                clManager.requestAlwaysAuthorization()
            default:
                break
            }
            refresh(jobs: jobs)
        } else {
            stopAll()
        }
    }

    /// Re-point the monitored regions at the current open jobs. Call whenever
    /// the job list changes; geocoding results are cached by address.
    func refresh(jobs: [WorkOrder]) {
        guard enabled, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let status = clManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }

        // Open jobs with an address, newest first, capped under the iOS limit.
        let candidates = jobs
            .filter { !$0.isSigned && !$0.customerAddress.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(Self.maxRegions)

        let wantedIds = Set(candidates.map { Self.regionPrefix + $0.id.uuidString })

        // Drop regions for jobs that are gone or signed.
        for region in clManager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            if !wantedIds.contains(region.identifier) {
                clManager.stopMonitoring(for: region)
            }
        }
        var infoMap = loadRegionInfo().filter { wantedIds.contains($0.key) }

        let alreadyMonitored = Set(clManager.monitoredRegions.map(\.identifier))
        for job in candidates {
            let identifier = Self.regionPrefix + job.id.uuidString
            infoMap[identifier] = RegionInfo(customerName: job.customerName, jobReference: job.jobReference)
            guard !alreadyMonitored.contains(identifier) else { continue }
            geocode(job.customerAddress) { [weak self] coordinate in
                guard let self, let coordinate else { return }
                let region = CLCircularRegion(center: coordinate, radius: Self.regionRadius, identifier: identifier)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                self.clManager.startMonitoring(for: region)
            }
        }
        saveRegionInfo(infoMap)
    }

    private func stopAll() {
        for region in clManager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            clManager.stopMonitoring(for: region)
        }
        saveRegionInfo([:])
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard enabled, region.identifier.hasPrefix(Self.regionPrefix) else { return }

        // Once per visit: skip if this job was reminded about recently.
        var lastNotified = (UserDefaults.standard.dictionary(forKey: Self.lastNotifiedKey) as? [String: Double]) ?? [:]
        let now = Date().timeIntervalSince1970
        if let last = lastNotified[region.identifier], now - last < Self.renotifyInterval { return }
        lastNotified[region.identifier] = now
        UserDefaults.standard.set(lastNotified, forKey: Self.lastNotifiedKey)

        let info = loadRegionInfo()[region.identifier]
        let content = UNMutableNotificationContent()
        content.title = "You're on site"
        if let info {
            content.body = info.jobReference.isEmpty
                ? "Get \(info.customerName)'s job signed off while you're here."
                : "Get \(info.customerName)'s job (\(info.jobReference)) signed off while you're here."
        } else {
            content.body = "Get this job signed off while you're here."
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: region.identifier,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Best-effort: a region that can't be monitored simply never fires.
    }

    // MARK: - Geocoding (cached by address string)

    private func geocode(_ address: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let cacheKey = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var cache = (UserDefaults.standard.dictionary(forKey: Self.coordinateCacheKey) as? [String: [Double]]) ?? [:]
        if let cached = cache[cacheKey], cached.count == 2 {
            completion(CLLocationCoordinate2D(latitude: cached[0], longitude: cached[1]))
            return
        }
        Task {
            guard let request = MKGeocodingRequest(addressString: address) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            do {
                let mapItems = try await request.mapItems
                guard let coordinate = mapItems.first?.location.coordinate else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                cache[cacheKey] = [coordinate.latitude, coordinate.longitude]
                UserDefaults.standard.set(cache, forKey: Self.coordinateCacheKey)
                DispatchQueue.main.async { completion(coordinate) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Region info persistence

    private func loadRegionInfo() -> [String: RegionInfo] {
        guard let data = UserDefaults.standard.data(forKey: Self.regionInfoKey),
              let decoded = try? JSONDecoder().decode([String: RegionInfo].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveRegionInfo(_ map: [String: RegionInfo]) {
        if let encoded = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(encoded, forKey: Self.regionInfoKey)
        }
    }
}
