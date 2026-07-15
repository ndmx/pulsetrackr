import CoreLocation

final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    /// The most recent location we've ever seen, persisted across launches so the
    /// map can open where the user was last instead of a hardcoded city. Readable
    /// without a live instance (e.g. from a view's `@State` initializer).
    static var lastKnownCoordinate: CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppStorageKey.lastKnownLatitude) != nil,
              defaults.object(forKey: AppStorageKey.lastKnownLongitude) != nil else { return nil }
        let coordinate = CLLocationCoordinate2D(
            latitude: defaults.double(forKey: AppStorageKey.lastKnownLatitude),
            longitude: defaults.double(forKey: AppStorageKey.lastKnownLongitude)
        )
        return coordinate.isValid ? coordinate : nil
    }

    private static func persist(_ coordinate: CLLocationCoordinate2D) {
        guard coordinate.isValid else { return }
        let defaults = UserDefaults.standard
        defaults.set(coordinate.latitude, forKey: AppStorageKey.lastKnownLatitude)
        defaults.set(coordinate.longitude, forKey: AppStorageKey.lastKnownLongitude)
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
            manager.startUpdatingLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func refreshCurrentLocationIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func setEmergencyTrackingActive(_ isActive: Bool) {
        manager.desiredAccuracy = isActive ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = isActive ? 10 : 50

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }

        if isActive {
            manager.startUpdatingLocation()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        accuracyAuthorization = manager.accuracyAuthorization
        guard let location = locations.last else { return }
        currentLocation = location
        currentCoordinate = location.coordinate
        Self.persist(location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        accuracyAuthorization = manager.accuracyAuthorization
        currentLocation = manager.location
        currentCoordinate = manager.location?.coordinate
    }
}
