import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/map_constants.dart';

class GeocodingService {
  Future<LatLng?> geocodeAddress(String address) async {
    try {
      final encodedAddress = Uri.encodeComponent(address);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=$encodedAddress'
        '&key=${MapConstants.googleMapsApiKey}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0] as Map<String, dynamic>;
          final geometry = result['geometry'] as Map<String, dynamic>;
          final location = geometry['location'] as Map<String, dynamic>;
          
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          
          return LatLng(lat, lng);
        } else {
          print('Geocoding API error: ${data['status']}');
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

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$encodedQuery'
        '&key=${MapConstants.googleMapsApiKey}'
        '&types=geocode',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final predictions = data['predictions'] as List;
          return predictions
              .map((prediction) => {
                    'description': (prediction as Map<String, dynamic>)['description'] as String,
                    'place_id': prediction['place_id'] as String,
                  })
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }

  Future<LatLng?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&key=${MapConstants.googleMapsApiKey}'
        '&fields=geometry',
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
          
          return LatLng(lat, lng);
        }
      }
      return null;
    } catch (e) {
      print('Error getting place details: $e');
      return null;
    }
  }

  // Reverse geocoding: Get address from coordinates
  Future<Map<String, dynamic>?> reverseGeocode(LatLng location) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${location.latitude},${location.longitude}'
        '&key=${MapConstants.googleMapsApiKey}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0] as Map<String, dynamic>;
          return {
            'address': result['formatted_address'] as String,
            'location': location,
            'place_id': result['place_id'] as String?,
          };
        }
      }
      return null;
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

