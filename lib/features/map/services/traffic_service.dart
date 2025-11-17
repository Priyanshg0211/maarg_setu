import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/map_constants.dart';

/// Traffic intensity levels
enum TrafficIntensity {
  none,      // Green - No traffic
  light,     // Yellow - Light traffic
  moderate,  // Orange - Moderate traffic
  heavy,     // Red - Heavy traffic
  severe,    // Dark Red - Severe traffic
}

/// Traffic data point for heatmap
class TrafficDataPoint {
  final LatLng location;
  final TrafficIntensity intensity;
  final double speedRatio; // 0.0 to 1.0 (1.0 = free flow, 0.0 = stopped)

  TrafficDataPoint({
    required this.location,
    required this.intensity,
    required this.speedRatio,
  });
}

class TrafficService {
  /// Get traffic data within a radius around a center point
  /// Samples points in a grid pattern within the circle
  /// Optimized to use fewer API calls while maintaining good coverage
  Future<List<TrafficDataPoint>> getTrafficDataInRadius({
    required LatLng center,
    required double radiusMeters,
  }) async {
    List<TrafficDataPoint> trafficPoints = [];
    
    // Optimized sampling: Use fewer points for better performance
    // Sample every 500 meters in a grid pattern
    const double stepDistance = 500; // Sample every 500 meters
    
    // Calculate grid bounds
    final double latStep = stepDistance / 111000; // Approximate meters to degrees
    final double lngStep = stepDistance / (111000 * math.cos(center.latitude * math.pi / 180));
    
    final int pointsPerSide = ((radiusMeters * 2) / stepDistance).ceil();
    final double startLat = center.latitude - (pointsPerSide * latStep / 2);
    final double startLng = center.longitude - (pointsPerSide * lngStep / 2);
    
    // Sample points in grid (optimized to skip some points)
    final List<Future<TrafficDataPoint?>> futures = [];
    
    for (int i = 0; i < pointsPerSide; i += 1) {
      for (int j = 0; j < pointsPerSide; j += 1) {
        final lat = startLat + (i * latStep);
        final lng = startLng + (j * lngStep);
        final point = LatLng(lat, lng);
        
        // Check if point is within radius
        final distance = _calculateDistance(center, point);
        if (distance <= radiusMeters) {
          // Add to futures list for parallel processing
          futures.add(_getTrafficForPoint(point));
        }
      }
    }
    
    // Process in batches to avoid overwhelming the API
    const int batchSize = 5;
    for (int i = 0; i < futures.length; i += batchSize) {
      final batch = futures.sublist(
        i,
        i + batchSize > futures.length ? futures.length : i + batchSize,
      );
      
      final results = await Future.wait(batch);
      trafficPoints.addAll(results.whereType<TrafficDataPoint>());
      
      // Small delay between batches
      if (i + batchSize < futures.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    
    return trafficPoints;
  }

  /// Get traffic data for a specific point by checking nearby routes
  Future<TrafficDataPoint?> _getTrafficForPoint(LatLng point) async {
    try {
      // Create a small route from point to nearby point to get traffic data
      // Use a point 100m away in a random direction
      final double bearing = math.Random().nextDouble() * 360;
      final nearbyPoint = _calculateOffset(point, 100, bearing);
      
      final url = Uri.parse(
        '${MapConstants.directionsApiUrl}'
        '?origin=${point.latitude},${point.longitude}'
        '&destination=${nearbyPoint.latitude},${nearbyPoint.longitude}'
        '&key=${MapConstants.googleMapsApiKey}'
        '&mode=driving'
        '&departure_time=now' // This enables traffic data
        '&traffic_model=best_guess',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['routes'] != null) {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final route = routes[0] as Map<String, dynamic>;
            final legs = route['legs'] as List;
            
            if (legs.isNotEmpty) {
              final leg = legs[0] as Map<String, dynamic>;
              
              // Get duration in traffic vs free flow
              final durationInTraffic = leg['duration_in_traffic'] as Map<String, dynamic>?;
              final duration = leg['duration'] as Map<String, dynamic>;
              
              if (durationInTraffic != null) {
                final freeFlowSeconds = duration['value'] as int;
                final trafficSeconds = durationInTraffic['value'] as int;
                
                // Calculate speed ratio (0.0 = stopped, 1.0 = free flow)
                final speedRatio = freeFlowSeconds > 0 
                    ? (freeFlowSeconds / trafficSeconds).clamp(0.0, 1.0)
                    : 1.0;
                
                // Determine intensity based on delay
                final delayRatio = (trafficSeconds - freeFlowSeconds) / freeFlowSeconds;
                final intensity = _getIntensityFromDelay(delayRatio, speedRatio);
                
                return TrafficDataPoint(
                  location: point,
                  intensity: intensity,
                  speedRatio: speedRatio,
                );
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error getting traffic data: $e');
    }
    
    return null;
  }

  /// Determine traffic intensity from delay ratio
  TrafficIntensity _getIntensityFromDelay(double delayRatio, double speedRatio) {
    if (speedRatio >= 0.9) {
      return TrafficIntensity.none;
    } else if (speedRatio >= 0.7) {
      return TrafficIntensity.light;
    } else if (speedRatio >= 0.5) {
      return TrafficIntensity.moderate;
    } else if (speedRatio >= 0.3) {
      return TrafficIntensity.heavy;
    } else {
      return TrafficIntensity.severe;
    }
  }

  /// Calculate distance between two points in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // meters
    final lat1Rad = point1.latitude * math.pi / 180;
    final lat2Rad = point2.latitude * math.pi / 180;
    final deltaLatRad = (point2.latitude - point1.latitude) * math.pi / 180;
    final deltaLngRad = (point2.longitude - point1.longitude) * math.pi / 180;
    
    final a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLngRad / 2) * math.sin(deltaLngRad / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Calculate offset point from a given point
  LatLng _calculateOffset(LatLng point, double distance, double bearing) {
    const double earthRadius = 6371000; // meters
    final lat1 = point.latitude * math.pi / 180;
    final lon1 = point.longitude * math.pi / 180;
    final bearingRad = bearing * math.pi / 180;
    
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(distance / earthRadius) +
      math.cos(lat1) * math.sin(distance / earthRadius) * math.cos(bearingRad),
    );
    
    final lon2 = lon1 + math.atan2(
      math.sin(bearingRad) * math.sin(distance / earthRadius) * math.cos(lat1),
      math.cos(distance / earthRadius) - math.sin(lat1) * math.sin(lat2),
    );
    
    return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  /// Get color for traffic intensity
  static Color getTrafficColor(TrafficIntensity intensity) {
    switch (intensity) {
      case TrafficIntensity.none:
        return Colors.green.withOpacity(0.3);
      case TrafficIntensity.light:
        return Colors.yellow.withOpacity(0.4);
      case TrafficIntensity.moderate:
        return Colors.orange.withOpacity(0.5);
      case TrafficIntensity.heavy:
        return Colors.red.withOpacity(0.6);
      case TrafficIntensity.severe:
        return const Color(0xFF8B0000).withOpacity(0.7); // Dark red
    }
  }
}

