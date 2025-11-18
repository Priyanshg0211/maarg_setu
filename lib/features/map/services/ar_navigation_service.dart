import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Service for handling AR navigation calculations and orientation
class ARNavigationService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  
  double _deviceBearing = 0.0;
  double _devicePitch = 0.0;
  double _deviceRoll = 0.0;
  
  final ValueNotifier<double> bearingNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> pitchNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> rollNotifier = ValueNotifier<double>(0.0);
  
  bool _isListening = false;
  
  /// Start listening to device sensors for orientation
  void startListening() {
    if (_isListening) return;
    _isListening = true;
    
    _accelerometerSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        // Calculate pitch and roll from accelerometer
        _devicePitch = math.atan2(
          event.x,
          math.sqrt(event.y * event.y + event.z * event.z),
        ) * 180 / math.pi;
        
        _deviceRoll = math.atan2(
          event.y,
          math.sqrt(event.x * event.x + event.z * event.z),
        ) * 180 / math.pi;
        
        pitchNotifier.value = _devicePitch;
        rollNotifier.value = _deviceRoll;
      },
    );
    
    _magnetometerSubscription = magnetometerEventStream().listen(
      (MagnetometerEvent event) {
        // Calculate bearing from magnetometer (simplified)
        _deviceBearing = math.atan2(event.y, event.x) * 180 / math.pi;
        bearingNotifier.value = _deviceBearing;
      },
    );
  }
  
  /// Stop listening to device sensors
  void stopListening() {
    _isListening = false;
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _magnetometerSubscription = null;
  }
  
  /// Calculate bearing from current location to target location
  double calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }
  
  /// Calculate distance between two points in meters
  double calculateDistance(LatLng from, LatLng to) {
    const double earthRadius = 6371000; // meters
    
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLat = (to.latitude - from.latitude) * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  /// Calculate angle difference between device bearing and target bearing
  double calculateAngleDifference(double deviceBearing, double targetBearing) {
    double diff = targetBearing - deviceBearing;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }
  
  /// Convert screen coordinates to AR world coordinates
  Offset worldToScreen(
    LatLng worldPoint,
    LatLng currentLocation,
    double deviceBearing,
    Size screenSize,
    double fieldOfView,
  ) {
    final bearing = calculateBearing(currentLocation, worldPoint);
    final angleDiff = calculateAngleDifference(deviceBearing, bearing);
    final distance = calculateDistance(currentLocation, worldPoint);
    
    // Convert angle to screen X position
    final normalizedAngle = angleDiff / (fieldOfView / 2);
    final screenX = (screenSize.width / 2) * (1 + normalizedAngle);
    
    // Convert distance to screen Y position (closer = higher on screen)
    final maxDistance = 1000.0; // meters
    final normalizedDistance = math.min(distance / maxDistance, 1.0);
    final screenY = screenSize.height * (0.3 + normalizedDistance * 0.5);
    
    return Offset(screenX, screenY);
  }
  
  /// Get current device bearing
  double get deviceBearing => _deviceBearing;
  
  /// Get current device pitch
  double get devicePitch => _devicePitch;
  
  /// Get current device roll
  double get deviceRoll => _deviceRoll;
  
  /// Dispose resources
  void dispose() {
    stopListening();
    bearingNotifier.dispose();
    pitchNotifier.dispose();
    rollNotifier.dispose();
  }
}

