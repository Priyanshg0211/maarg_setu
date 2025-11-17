import 'package:location/location.dart';

class LocationService {
  LocationService();

  final Location _location = Location();

  Future<bool> _ensureServiceEnabled() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
    }
    return serviceEnabled;
  }

  Future<bool> _ensurePermissionGranted() async {
    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
    }
    return permissionGranted == PermissionStatus.granted;
  }

  Future<bool> canAccessLocation() async {
    final serviceEnabled = await _ensureServiceEnabled();
    if (!serviceEnabled) return false;
    final permissionGranted = await _ensurePermissionGranted();
    return permissionGranted;
  }

  Future<LocationData> getCurrentLocation() => _location.getLocation();

  Stream<LocationData> locationStream() => _location.onLocationChanged;
}
