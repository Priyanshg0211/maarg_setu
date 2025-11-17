import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import '../../../../core/constants/map_constants.dart';

class RouteDetails {
  final List<LatLng> points;
  final String distance;
  final String duration;
  final String distanceValue; // in meters
  final int durationValue; // in seconds

  RouteDetails({
    required this.points,
    required this.distance,
    required this.duration,
    required this.distanceValue,
    required this.durationValue,
  });
}

class DirectionsService {
  Future<RouteDetails?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      // Build the Directions API URL with proper encoding
      // Using alternatives=true to get the best route
      final url = Uri.parse(
        '${MapConstants.directionsApiUrl}'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=${MapConstants.googleMapsApiKey}'
        '&mode=driving'
        '&alternatives=false', // Set to true if you want multiple route options
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final route = routes[0] as Map<String, dynamic>;
            
            // Get detailed polylines from all legs and steps for accurate road-following
            final legs = route['legs'] as List;
            List<LatLng> allRoutePoints = [];
            
            for (var leg in legs) {
              final steps = leg['steps'] as List;
              for (var step in steps) {
                final stepPolyline = step['polyline'] as Map<String, dynamic>;
                final polylineString = stepPolyline['points'] as String;
                
                // Decode each step's polyline for detailed route
                final decodedPoints = decodePolyline(polylineString);
                if (decodedPoints.isNotEmpty) {
                  final stepPoints = decodedPoints
                      .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
                      .toList();
                  allRoutePoints.addAll(stepPoints);
                }
              }
            }
            
            // Get route summary (distance and duration)
            String distance = '';
            String duration = '';
            String distanceValue = '0';
            int durationValue = 0;
            
            if (legs.isNotEmpty) {
              final firstLeg = legs[0] as Map<String, dynamic>;
              final distanceInfo = firstLeg['distance'] as Map<String, dynamic>;
              final durationInfo = firstLeg['duration'] as Map<String, dynamic>;
              
              distance = distanceInfo['text'] as String;
              duration = durationInfo['text'] as String;
              distanceValue = (distanceInfo['value'] as int).toString();
              durationValue = durationInfo['value'] as int;
            }
            
            // If detailed steps are available, use them; otherwise fall back to overview
            List<LatLng> routePoints = [];
            if (allRoutePoints.isNotEmpty) {
              routePoints = allRoutePoints;
            } else {
              // Fallback to overview polyline if steps are not available
              final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>;
              final polyline = overviewPolyline['points'] as String;
              final decodedPoints = decodePolyline(polyline);
              
              if (decodedPoints.isNotEmpty) {
                routePoints = decodedPoints
                    .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
                    .toList();
              }
            }
            
            if (routePoints.isNotEmpty) {
              return RouteDetails(
                points: routePoints,
                distance: distance,
                duration: duration,
                distanceValue: distanceValue,
                durationValue: durationValue,
              );
            }
          }
        } else {
          print('Directions API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return null;
        }
      } else {
        print('HTTP error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error getting directions: $e');
      return null;
    }
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

