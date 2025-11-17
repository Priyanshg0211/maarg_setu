import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import '../../../../core/constants/map_constants.dart';

class NavigationStep {
  final String instruction;
  final String distance;
  final String duration;
  final LatLng location;
  final String maneuver; // e.g., "turn-left", "straight", "turn-right"
  final int stepNumber;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.location,
    required this.maneuver,
    required this.stepNumber,
  });
}

class RouteDetails {
  final List<LatLng> points;
  final String distance;
  final String duration;
  final String distanceValue; // in meters
  final int durationValue; // in seconds
  final List<NavigationStep> steps;
  final String summary; // Route summary text

  RouteDetails({
    required this.points,
    required this.distance,
    required this.duration,
    required this.distanceValue,
    required this.durationValue,
    required this.steps,
    required this.summary,
  });
}

class DirectionsService {
  Future<List<RouteDetails>> getRoutes({
    required LatLng origin,
    required LatLng destination,
    bool alternatives = true,
  }) async {
    try {
      // Build the Directions API URL with proper encoding
      final url = Uri.parse(
        '${MapConstants.directionsApiUrl}'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=${MapConstants.googleMapsApiKey}'
        '&mode=driving'
        '&alternatives=$alternatives',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;
          List<RouteDetails> routeList = [];
          
          for (var routeData in routes) {
            final route = routeData as Map<String, dynamic>;
            final routeDetails = _parseRoute(route);
            if (routeDetails != null) {
              routeList.add(routeDetails);
            }
          }
          
          return routeList;
        } else {
          print('Directions API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return [];
        }
      } else {
        print('HTTP error: ${response.statusCode} - ${response.body}');
        // Fallback: Create a simple route with straight line
        return _createFallbackRoute(origin, destination);
      }
    } catch (e) {
      print('Error getting directions: $e');
      // Fallback: Create a simple route with straight line
      return _createFallbackRoute(origin, destination);
    }
  }

  // Create a fallback route when API fails - always show a path
  List<RouteDetails> _createFallbackRoute(LatLng origin, LatLng destination) {
    // Create a simple straight line path
    final fallbackPoints = _createInterpolatedPath(origin, destination);
    final distance = _calculateDistance(origin, destination);
    
    return [
      RouteDetails(
        points: fallbackPoints,
        distance: _formatDistance(distance.round()),
        duration: _formatDuration((distance / 13.9).round()), // Estimate based on average speed
        distanceValue: distance.round().toString(),
        durationValue: (distance / 13.9).round(),
        steps: [
          NavigationStep(
            instruction: 'Go straight to destination',
            distance: _formatDistance(distance.round()),
            duration: _formatDuration((distance / 13.9).round()),
            location: destination,
            maneuver: 'straight',
            stepNumber: 0,
          ),
        ],
        summary: 'Direct route',
      ),
    ];
  }

  // Create an interpolated path between two points for better visualization
  List<LatLng> _createInterpolatedPath(LatLng origin, LatLng destination) {
    List<LatLng> points = [origin];
    const int segments = 50; // Number of intermediate points
    
    for (int i = 1; i < segments; i++) {
      final ratio = i / segments;
      final lat = origin.latitude + (destination.latitude - origin.latitude) * ratio;
      final lng = origin.longitude + (destination.longitude - origin.longitude) * ratio;
      points.add(LatLng(lat, lng));
    }
    
    points.add(destination);
    return points;
  }

  // Calculate distance between two points in meters
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

  RouteDetails? _parseRoute(Map<String, dynamic> route) {
    try {
      final legs = route['legs'] as List;
      if (legs.isEmpty) return null;
      
      List<LatLng> allRoutePoints = [];
      List<NavigationStep> navigationSteps = [];
      String distance = '';
      String duration = '';
      String distanceValue = '0';
      int durationValue = 0;
      String summary = route['summary'] as String? ?? '';
      
      int stepNumber = 0;
      
      for (var leg in legs) {
        final legData = leg as Map<String, dynamic>;
        final steps = legData['steps'] as List;
        
        // Aggregate distance and duration from all legs
        final legDistance = legData['distance'] as Map<String, dynamic>;
        final legDuration = legData['duration'] as Map<String, dynamic>;
        
        if (distance.isEmpty) {
          distance = legDistance['text'] as String;
          duration = legDuration['text'] as String;
          distanceValue = (legDistance['value'] as int).toString();
          durationValue = legDuration['value'] as int;
        } else {
          // Add to total if multiple legs
          distanceValue = (int.parse(distanceValue) + (legDistance['value'] as int)).toString();
          durationValue += legDuration['value'] as int;
        }
        
        for (var step in steps) {
          final stepData = step as Map<String, dynamic>;
          final stepPolyline = stepData['polyline'] as Map<String, dynamic>;
          final polylineString = stepPolyline['points'] as String;
          
          // Decode step polyline using google_polyline_algorithm package
          final decodedPoints = decodePolyline(polylineString);
          if (decodedPoints.isNotEmpty) {
            final stepPoints = decodedPoints
                .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
                .toList();
            allRoutePoints.addAll(stepPoints);
          }
          
          // Extract navigation step information
          final stepDistance = stepData['distance'] as Map<String, dynamic>;
          final stepDuration = stepData['duration'] as Map<String, dynamic>;
          final endLocation = stepData['end_location'] as Map<String, dynamic>;
          final htmlInstructions = stepData['html_instructions'] as String? ?? '';
          final maneuver = stepData['maneuver'] as String? ?? 'straight';
          
          // Clean HTML from instructions
          final instruction = htmlInstructions
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll('&nbsp;', ' ')
              .trim();
          
          navigationSteps.add(
            NavigationStep(
              instruction: instruction.isNotEmpty ? instruction : 'Continue',
              distance: stepDistance['text'] as String,
              duration: stepDuration['text'] as String,
              location: LatLng(
                endLocation['lat'] as double,
                endLocation['lng'] as double,
              ),
              maneuver: maneuver,
              stepNumber: stepNumber++,
            ),
          );
        }
      }
      
      // If no detailed points, use overview polyline
      List<LatLng> routePoints = [];
      if (allRoutePoints.isNotEmpty) {
        routePoints = allRoutePoints;
      } else {
        final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>;
        final polyline = overviewPolyline['points'] as String;
        
        // Decode overview polyline using google_polyline_algorithm package
        final decodedPoints = decodePolyline(polyline);
        if (decodedPoints.isNotEmpty) {
          routePoints = decodedPoints
              .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
              .toList();
        }
      }
      
      // Always ensure we have at least a path - create fallback if empty
      if (routePoints.isEmpty) {
        // Get origin and destination from legs
        if (legs.isNotEmpty) {
          final firstLeg = legs[0] as Map<String, dynamic>;
          final lastLeg = legs[legs.length - 1] as Map<String, dynamic>;
          final startLocation = firstLeg['start_location'] as Map<String, dynamic>;
          final endLocation = lastLeg['end_location'] as Map<String, dynamic>;
          
          final origin = LatLng(
            startLocation['lat'] as double,
            startLocation['lng'] as double,
          );
          final dest = LatLng(
            endLocation['lat'] as double,
            endLocation['lng'] as double,
          );
          
          routePoints = _createInterpolatedPath(origin, dest);
        } else {
          return null;
        }
      }
      
      // Use API-provided formatted text, or format if empty
      final totalDistance = distance.isNotEmpty ? distance : _formatDistance(int.parse(distanceValue));
      final totalDuration = duration.isNotEmpty ? duration : _formatDuration(durationValue);
      
      return RouteDetails(
        points: routePoints,
        distance: totalDistance,
        duration: totalDuration,
        distanceValue: distanceValue,
        durationValue: durationValue,
        steps: navigationSteps,
        summary: summary,
      );
    } catch (e) {
      print('Error parsing route: $e');
      return null;
    }
  }

  String _formatDistance(int meters) {
    if (meters < 1000) {
      return '$meters m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds sec';
    } else if (seconds < 3600) {
      return '${(seconds / 60).round()} min';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      if (minutes == 0) {
        return '$hours hr';
      } else {
        return '$hours hr $minutes min';
      }
    }
  }

  // Get single route (for backward compatibility)
  Future<RouteDetails?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final routes = await getRoutes(origin: origin, destination: destination, alternatives: false);
    return routes.isNotEmpty ? routes[0] : null;
  }

  // Legacy method for backward compatibility
  Future<List<LatLng>?> getRoutePoints({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await getRoute(origin: origin, destination: destination);
    return route?.points;
  }

  // Fallback: Create a simple straight line if API fails
  List<LatLng> createStraightLine(LatLng origin, LatLng destination) {
    return [origin, destination];
  }
}

