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

#if DEBUG
#Preview {
    NavigationStack {
        PulseMapView()
            .environmentObject(IncidentStore.preview)
            .environmentObject(LocationManager())
            .environmentObject(SOSStore())
    }
}
#endif
