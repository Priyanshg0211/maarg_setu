import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import '../../../../core/constants/map_constants.dart';

class DirectionsService {
  Future<List<LatLng>?> getRoutePoints({
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
            
            // If detailed steps are available, use them; otherwise fall back to overview
            if (allRoutePoints.isNotEmpty) {
              return allRoutePoints;
            } else {
              // Fallback to overview polyline if steps are not available
              final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>;
              final polyline = overviewPolyline['points'] as String;
              final decodedPoints = decodePolyline(polyline);
              
              if (decodedPoints.isNotEmpty) {
                return decodedPoints
                    .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
                    .toList();
              }
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

  // Fallback: Create a simple straight line if API fails
  List<LatLng> createStraightLine(LatLng origin, LatLng destination) {
    return [origin, destination];
  }
}

