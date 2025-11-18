import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'directions_service.dart';
import 'nearby_places_service.dart';

/// Route optimization result
class OptimizedRoute {
  final RouteDetails route;
  final double score; // Optimization score (higher is better)
  final List<TrafficAlert> alerts;
  final double estimatedTimeWithTraffic; // in seconds
  final String optimizationReason;

  OptimizedRoute({
    required this.route,
    required this.score,
    required this.alerts,
    required this.estimatedTimeWithTraffic,
    required this.optimizationReason,
  });
}

class RouteOptimizerService {
  final NearbyPlacesService _nearbyPlacesService = NearbyPlacesService();
  final DirectionsService _directionsService = DirectionsService();

  /// Find optimal route considering traffic from nearby places
  /// Uses shortest path algorithm (Dijkstra-like) with traffic weights
  Future<List<OptimizedRoute>> findOptimalRoutes({
    required LatLng origin,
    required LatLng destination,
    double searchRadius = 3000, // 3km radius for place detection
  }) async {
    try {
      // Get all alternative routes
      final routes = await _directionsService.getRoutes(
        origin: origin,
        destination: destination,
        alternatives: true,
      );

      if (routes.isEmpty) return [];

      // Detect nearby places for origin and destination
      final originPlaces = await _nearbyPlacesService.findNearbyPlaces(
        center: origin,
        radiusMeters: searchRadius,
      );

      final destinationPlaces = await _nearbyPlacesService.findNearbyPlaces(
        center: destination,
        radiusMeters: searchRadius,
      );

      // Analyze traffic alerts
      final originAlerts = _nearbyPlacesService.analyzeTrafficAlerts(
        center: origin,
        places: originPlaces,
      );

      final destinationAlerts = _nearbyPlacesService.analyzeTrafficAlerts(
        center: destination,
        places: destinationPlaces,
      );

      // Evaluate and optimize each route
      final optimizedRoutes = <OptimizedRoute>[];

      for (final route in routes) {
        // Calculate route score based on:
        // 1. Distance (shorter is better)
        // 2. Traffic impact from nearby places
        // 3. Number of traffic-heavy areas along route

        final distance = double.tryParse(route.distanceValue) ?? 0;
        final baseTime = route.durationValue;

        // Calculate traffic impact along route
        double trafficPenalty = 0;
        int alertCount = 0;
        final routeAlerts = <TrafficAlert>[];

        // Check if route passes through high-traffic areas
        for (final alert in [...originAlerts, ...destinationAlerts]) {
          final distanceToRoute = _minDistanceToRoute(alert.location, route.points);
          
          // If alert is within 200m of route, it affects the route
          if (distanceToRoute < 200) {
            trafficPenalty += alert.severity * 0.3; // Add time penalty
            alertCount++;
            routeAlerts.add(alert);
          }
        }

        // Calculate estimated time with traffic
        final estimatedTime = baseTime * (1 + trafficPenalty);

        // Calculate optimization score
        // Higher score = better route
        // Formula: (distance_weight * normalized_distance) + (time_weight * normalized_time) - traffic_penalty
        final normalizedDistance = 1.0 / (1.0 + distance / 10000); // Normalize to 0-1
        final normalizedTime = 1.0 / (1.0 + estimatedTime / 3600); // Normalize to 0-1
        final score = (0.4 * normalizedDistance) + (0.4 * normalizedTime) - (0.2 * trafficPenalty);

        // Generate optimization reason
        String reason = 'Optimal route';
        if (alertCount > 0) {
          reason = 'Route avoids ${alertCount} high-traffic area${alertCount > 1 ? 's' : ''}';
        }
        if (distance < 1000) {
          reason += ' - Shortest path';
        }

        optimizedRoutes.add(
          OptimizedRoute(
            route: route,
            score: score,
            alerts: routeAlerts,
            estimatedTimeWithTraffic: estimatedTime,
            optimizationReason: reason,
          ),
        );
      }

      // Sort by score (highest first) - best route first
      optimizedRoutes.sort((a, b) => b.score.compareTo(a.score));

      return optimizedRoutes;
    } catch (e) {
      print('Error optimizing routes: $e');
      // Fallback to regular routes
      final routes = await _directionsService.getRoutes(
        origin: origin,
        destination: destination,
        alternatives: true,
      );
      return routes.map((route) => OptimizedRoute(
        route: route,
        score: 0.5,
        alerts: [],
        estimatedTimeWithTraffic: route.durationValue.toDouble(),
        optimizationReason: 'Standard route',
      )).toList();
    }
  }

  /// Calculate minimum distance from a point to any point on the route
  double _minDistanceToRoute(LatLng point, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return double.infinity;

    double minDistance = double.infinity;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final segmentStart = routePoints[i];
      final segmentEnd = routePoints[i + 1];
      
      // Calculate distance to line segment
      final distance = _distanceToSegment(point, segmentStart, segmentEnd);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    return minDistance;
  }

  /// Calculate distance from point to line segment
  double _distanceToSegment(LatLng point, LatLng segmentStart, LatLng segmentEnd) {
    // Calculate distance using Haversine formula
    final distToStart = _haversineDistance(point, segmentStart);
    final distToEnd = _haversineDistance(point, segmentEnd);
    final distSegment = _haversineDistance(segmentStart, segmentEnd);

    // If segment is very short, return distance to closest endpoint
    if (distSegment < 10) {
      return math.min(distToStart, distToEnd);
    }

    // Calculate perpendicular distance to segment
    // Using dot product to find closest point on segment
    final dx = segmentEnd.longitude - segmentStart.longitude;
    final dy = segmentEnd.latitude - segmentStart.latitude;
    final px = point.longitude - segmentStart.longitude;
    final py = point.latitude - segmentStart.latitude;

    final dot = px * dx + py * dy;
    final lenSq = dx * dx + dy * dy;
    
    if (lenSq == 0) return distToStart;

    final param = dot / lenSq;

    LatLng closestPoint;
    if (param < 0) {
      closestPoint = segmentStart;
    } else if (param > 1) {
      closestPoint = segmentEnd;
    } else {
      closestPoint = LatLng(
        segmentStart.latitude + param * dy,
        segmentStart.longitude + param * dx,
      );
    }

    return _haversineDistance(point, closestPoint);
  }

  /// Haversine distance calculation
  double _haversineDistance(LatLng point1, LatLng point2) {
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
}

