import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/map_constants.dart';

class GeocodingService {
  /// Geocoding API: Convert address to coordinates
  /// Uses: https://maps.googleapis.com/maps/api/geocode/json
  Future<LatLng?> geocodeAddress(String address) async {
    try {
      final encodedAddress = Uri.encodeComponent(address);
      final url = Uri.parse(
        '${MapConstants.geocodingApiUrl}'
        '?address=$encodedAddress'
        '&key=${MapConstants.googleMapsApiKey}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['results'] != null && (data['results'] as List).isNotEmpty) {
          final result = data['results'][0] as Map<String, dynamic>;
          final geometry = result['geometry'] as Map<String, dynamic>;
          final location = geometry['location'] as Map<String, dynamic>;
          
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          
          return LatLng(lat, lng);
        } else {
          print('Geocoding API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return null;
        }
      } else {
        print('HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error geocoding address: $e');
      return null;
    }
  }

  /// Places API Autocomplete: Search for places and addresses
  /// Uses: https://maps.googleapis.com/maps/api/place/autocomplete/json
  Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    LatLng? location,
    double? radius,
  }) async {
    try {
      if (query.isEmpty) {
        return [];
      }

      final encodedQuery = Uri.encodeComponent(query);
      String url = '${MapConstants.placesAutocompleteApiUrl}'
          '?input=$encodedQuery'
          '&key=${MapConstants.googleMapsApiKey}';
      
      // Add location bias for better results (like Google Maps)
      if (location != null) {
        url += '&location=${location.latitude},${location.longitude}';
        url += '&radius=${radius ?? 50000}'; // 50km default radius
      }
      
      // Include establishments and addresses
      url += '&types=(geocode|establishment)';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final predictions = data['predictions'] as List;
          return predictions
              .map((prediction) {
                final pred = prediction as Map<String, dynamic>;
                return {
                  'description': pred['description'] as String,
                  'place_id': pred['place_id'] as String,
                  'structured_formatting': pred['structured_formatting'] as Map<String, dynamic>?,
                };
              })
              .toList();
        } else if (data['status'] == 'ZERO_RESULTS') {
          return [];
        } else {
          print('Places API Autocomplete error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return [];
        }
      } else {
        print('HTTP error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }

  /// Places API Details: Get detailed information about a place
  /// Uses: https://maps.googleapis.com/maps/api/place/details/json
  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        '${MapConstants.placeDetailsApiUrl}'
        '?place_id=$placeId'
        '&key=${MapConstants.googleMapsApiKey}'
        '&fields=geometry,name,formatted_address,vicinity',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'] as Map<String, dynamic>;
          final geometry = result['geometry'] as Map<String, dynamic>;
          final location = geometry['location'] as Map<String, dynamic>;
          
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          
          return {
            'location': LatLng(lat, lng),
            'name': result['name'] as String? ?? '',
            'address': result['formatted_address'] as String? ?? result['vicinity'] as String? ?? '',
          };
        } else {
          print('Places API Details error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return null;
        }
      } else {
        print('HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting place details: $e');
      return null;
    }
  }

  // Legacy method for backward compatibility
  Future<LatLng?> getPlaceLocation(String placeId) async {
    final details = await getPlaceDetails(placeId);
    return details?['location'] as LatLng?;
  }

  /// Geocoding API: Reverse geocoding - Get address from coordinates
  /// Uses: https://maps.googleapis.com/maps/api/geocode/json
  Future<Map<String, dynamic>?> reverseGeocode(LatLng location) async {
    try {
      final url = Uri.parse(
        '${MapConstants.geocodingApiUrl}'
        '?latlng=${location.latitude},${location.longitude}'
        '&key=${MapConstants.googleMapsApiKey}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['results'] != null && (data['results'] as List).isNotEmpty) {
          final result = data['results'][0] as Map<String, dynamic>;
          return {
            'address': result['formatted_address'] as String,
            'location': location,
            'place_id': result['place_id'] as String?,
          };
        } else {
          print('Reverse Geocoding API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return null;
        }
      } else {
        print('HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error reverse geocoding: $e');
      return null;
    }
  }

  // Snap to roads using Directions API (fallback method)
  Future<LatLng?> snapToRoad(LatLng location) async {
    try {
      // Use Directions API with waypoints to snap to nearest road
      // This is a workaround since Roads API requires billing
      final url = Uri.parse(
        '${MapConstants.directionsApiUrl}'
        '?origin=${location.latitude},${location.longitude}'
        '&destination=${location.latitude},${location.longitude}'
        '&key=${MapConstants.googleMapsApiKey}'
        '&mode=driving',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0] as Map<String, dynamic>;
          final legs = route['legs'] as List;
          if (legs.isNotEmpty) {
            final leg = legs[0] as Map<String, dynamic>;
            final startLocation = leg['start_location'] as Map<String, dynamic>;
            return LatLng(
              startLocation['lat'] as double,
              startLocation['lng'] as double,
            );
          }
        }
      }
      // If snapping fails, return original location
      return location;
    } catch (e) {
      print('Error snapping to road: $e');
      return location;
    }
  }
}

