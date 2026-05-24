import SwiftUI

struct PulseMapView: View {
    var body: some View {
        #if canImport(MapboxMaps)
        MapboxIncidentMapView()
        #else
        IncidentMapView()
        #endif
    }
}

#Preview {
    NavigationStack {
        PulseMapView()
            .environmentObject(IncidentStore())
            .environmentObject(LocationManager())
    }
}
