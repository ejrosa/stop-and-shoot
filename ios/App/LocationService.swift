import CoreLocation
import Foundation
import StopAndShootLogic

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var wantsUpdates = false
    private var fixInProgress = false
    private var updating = false
    private var latest: CLLocation?
    private var authWait: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var fixWait: CheckedContinuation<LocationFix, Error>?
    var onChange: (@MainActor () -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
    }

    func setWantsUpdates(_ wants: Bool) {
        wantsUpdates = wants
        refreshUpdates()
    }

    func requestPermission() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func gpsLine() -> String {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return "Location off"
        case .notDetermined:
            return "Location not set"
        default:
            break
        }
        guard CLLocationManager.locationServicesEnabled() else { return "Location Services are off" }
        guard let latest, latest.horizontalAccuracy >= 0 else { return "Waiting for GPS" }
        if Date().timeIntervalSince(latest.timestamp) > 30 { return "Waiting for GPS" }
        return "GPS ready · ±\(Int(latest.horizontalAccuracy.rounded())) m"
    }

    func currentFix(maxAge: TimeInterval) async throws -> LocationFix {
        let status = await ensureAuthorized()
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            throw MarkFailure.permissionDenied
        }
        guard CLLocationManager.locationServicesEnabled() else { throw MarkFailure.servicesOff }
        if let latest, Date().timeIntervalSince(latest.timestamp) < maxAge, latest.horizontalAccuracy >= 0 {
            return convert(latest)
        }
        fixInProgress = true
        refreshUpdates()
        defer {
            fixInProgress = false
            refreshUpdates()
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LocationFix, Error>) in
            fixWait = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(MarkingPolicy.fixTimeout * 1_000_000_000))
                self.finishFix(.failure(MarkFailure.timedOut))
            }
        }
    }

    private func ensureAuthorized() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        if status != .notDetermined { return status }
        return await withCheckedContinuation { continuation in
            authWait = continuation
            manager.requestWhenInUseAuthorization()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if let waiter = self.authWait {
                    self.authWait = nil
                    waiter.resume(returning: self.manager.authorizationStatus)
                }
            }
        }
    }

    private func refreshUpdates() {
        let status = manager.authorizationStatus
        let allowed = status == .authorizedAlways || status == .authorizedWhenInUse
        if allowed && (wantsUpdates || fixInProgress) {
            if !updating {
                manager.startUpdatingLocation()
                updating = true
            }
        } else if updating {
            manager.stopUpdatingLocation()
            updating = false
        }
    }

    private func convert(_ location: CLLocation) -> LocationFix {
        LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }

    private func finishFix(_ result: Result<LocationFix, Error>) {
        guard let waiter = fixWait else { return }
        fixWait = nil
        waiter.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status != .notDetermined, let waiter = self.authWait {
                self.authWait = nil
                waiter.resume(returning: status)
            }
            self.refreshUpdates()
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let locations = locations
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.latest = location
            if location.horizontalAccuracy >= 0 {
                self.finishFix(.success(self.convert(location)))
            }
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor in
            if code == .locationUnknown { return }
            if code == .denied {
                self.finishFix(.failure(MarkFailure.permissionDenied))
            }
            self.onChange?()
        }
    }
}
