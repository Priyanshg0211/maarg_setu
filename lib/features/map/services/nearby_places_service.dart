import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/map_constants.dart';

/// Place types that affect traffic (hyperlocal focused)
enum PlaceType {
  school,
  university,
  mall,
  shoppingMall,
  cafe,
  restaurant,
  market,
  store,
  hospital,
  parking,
  busStation,
  trainStation,
  // Hyperlocal specific
  vendor,
  localMarket,
  foodStall,
  pharmacy,
  bank,
  atm,
  gasStation,
  postOffice,
  laundry,
  beautySalon,
  bakery,
  other,
}

/// Nearby place information
class NearbyPlace {
  final String placeId;
  final String name;
  final LatLng location;
  final PlaceType type;
  final double? rating;
  final int? userRatingsTotal;
  final String? vicinity;
  final double distance; // Distance from center in meters

  NearbyPlace({
    required this.placeId,
    required this.name,
    required this.location,
    required this.type,
    this.rating,
    this.userRatingsTotal,
    this.vicinity,
    required this.distance,
  });

  /// Get traffic impact score (0.0 to 1.0)
  /// Higher score = more traffic impact
  double get trafficImpact {
    switch (type) {
      case PlaceType.school:
      case PlaceType.university:
        return 0.8; // High traffic during school hours
      case PlaceType.mall:
      case PlaceType.shoppingMall:
        return 0.7; // High traffic, especially weekends
      case PlaceType.market:
      case PlaceType.localMarket:
        return 0.9; // Very high traffic
      case PlaceType.vendor:
      case PlaceType.foodStall:
        return 0.85; // Very high traffic - hyperlocal vendors
      case PlaceType.cafe:
      case PlaceType.restaurant:
        return 0.5; // Moderate traffic
      case PlaceType.busStation:
      case PlaceType.trainStation:
        return 0.85; // Very high traffic
      case PlaceType.hospital:
        return 0.6; // Moderate to high traffic
      case PlaceType.parking:
        return 0.4; // Low to moderate
      case PlaceType.store:
        return 0.3; // Low traffic
      case PlaceType.pharmacy:
      case PlaceType.bank:
      case PlaceType.atm:
        return 0.4; // Moderate traffic
      case PlaceType.gasStation:
        return 0.5; // Moderate to high
      case PlaceType.bakery:
        return 0.6; // High during morning hours
      default:
        return 0.2;
    }
  }
}

/// Traffic alert based on nearby places
class TrafficAlert {
  final String message;
  final LatLng location;
  final double severity; // 0.0 to 1.0
  final List<NearbyPlace> contributingPlaces;
  final PlaceType primaryType;

  TrafficAlert({
    required this.message,
    required this.location,
    required this.severity,
    required this.contributingPlaces,
    required this.primaryType,
  });

  String get severityLevel {
    if (severity >= 0.8) return 'High';
    if (severity >= 0.5) return 'Medium';
    return 'Low';
  }
}

class NearbyPlacesService {
  /// Search for nearby places using Places API (Nearby Search)
  Future<List<NearbyPlace>> findNearbyPlaces({
    required LatLng center,
    required double radiusMeters,
    List<String>? placeTypes,
  }) async {
    try {
      // Default place types to search for (hyperlocal focused)
      final types = placeTypes ?? [
        'school',
        'university',
        'shopping_mall',
        'cafe',
        'restaurant',
        'supermarket',
        'market',
        'store',
        'hospital',
        'parking',
        'bus_station',
        'train_station',
        'subway_station',
        // Hyperlocal specific places
        'food',
        'bakery',
        'pharmacy',
        'bank',
        'atm',
        'gas_station',
        'local_government_office',
        'post_office',
        'laundry',
        'hair_care',
        'beauty_salon',
      ];

      List<NearbyPlace> allPlaces = [];

      // Search for each place type
      for (final type in types) {
        try {
          final url = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
            '?location=${center.latitude},${center.longitude}'
            '&radius=${radiusMeters.toInt()}'
            '&type=$type'
            '&key=${MapConstants.googleMapsApiKey}',
          );

          final response = await http.get(url);

          if (response.statusCode == 200) {
            final data = json.decode(response.body) as Map<String, dynamic>;

            if (data['status'] == 'OK' && data['results'] != null) {
              final results = data['results'] as List<dynamic>;

              for (final result in results) {
                final place = result as Map<String, dynamic>;
                final geometry = place['geometry'] as Map<String, dynamic>;
                final location = geometry['location'] as Map<String, dynamic>;

                final placeLocation = LatLng(
                  location['lat'] as double,
                  location['lng'] as double,
                );

                final distance = _calculateDistance(center, placeLocation);

                final placeType = _parsePlaceType(
                  place['types'] as List<dynamic>? ?? [],
                );

                allPlaces.add(
                  NearbyPlace(
                    placeId: place['place_id'] as String,
                    name: place['name'] as String,
                    location: placeLocation,
                    type: placeType,
                    rating: (place['rating'] as num?)?.toDouble(),
                    userRatingsTotal: place['user_ratings_total'] as int?,
                    vicinity: place['vicinity'] as String?,
                    distance: distance,
                  ),
                );
              }
            }
          }

          // Small delay to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          print('Error searching for place type $type: $e');
        }
      }

      // Remove duplicates and sort by distance
      final uniquePlaces = <String, NearbyPlace>{};
      for (final place in allPlaces) {
        if (!uniquePlaces.containsKey(place.placeId)) {
          uniquePlaces[place.placeId] = place;
        }
      }

      return uniquePlaces.values.toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));
    } catch (e) {
      print('Error finding nearby places: $e');
      return [];
    }
  }

  /// Analyze traffic alerts based on nearby places
  List<TrafficAlert> analyzeTrafficAlerts({
    required LatLng center,
    required List<NearbyPlace> places,
    double radiusMeters = 500, // Analyze within 500m radius
  }) {
    final alerts = <TrafficAlert>[];

    // Group places by type and location clusters
    final clusters = <String, List<NearbyPlace>>{};

    for (final place in places) {
      if (place.distance > radiusMeters) continue;

      final clusterKey = place.type.toString();
      clusters.putIfAbsent(clusterKey, () => []).add(place);
    }

    // Create alerts for each cluster
    for (final entry in clusters.entries) {
      final placesInCluster = entry.value;
      if (placesInCluster.isEmpty) continue;

      // Calculate average location
      double avgLat = 0;
      double avgLng = 0;
      double totalImpact = 0;

      for (final place in placesInCluster) {
        avgLat += place.location.latitude;
        avgLng += place.location.longitude;
        totalImpact += place.trafficImpact;
      }

      avgLat /= placesInCluster.length;
      avgLng /= placesInCluster.length;
      final avgImpact = totalImpact / placesInCluster.length;

      // Only create alert if impact is significant
      if (avgImpact >= 0.4) {
        final primaryType = placesInCluster.first.type;
        final message = _generateAlertMessage(primaryType, placesInCluster.length);

        alerts.add(
          TrafficAlert(
            message: message,
            location: LatLng(avgLat, avgLng),
            severity: avgImpact,
            contributingPlaces: placesInCluster,
            primaryType: primaryType,
          ),
        );
      }
    }

    // Sort by severity (highest first)
    alerts.sort((a, b) => b.severity.compareTo(a.severity));

    return alerts;
  }

  /// Generate alert message based on place type and count (hyperlocal focused)
  String _generateAlertMessage(PlaceType type, int count) {
    switch (type) {
      case PlaceType.school:
      case PlaceType.university:
        return count > 1
            ? '$count schools/colleges nearby - Avoid 8-9 AM & 3-4 PM'
            : 'School nearby - Heavy traffic during drop-off/pick-up times';
      case PlaceType.mall:
      case PlaceType.shoppingMall:
        return count > 1
            ? '$count shopping areas nearby - Busy on weekends'
            : 'Shopping area nearby - Peak hours: 10 AM - 8 PM';
      case PlaceType.market:
      case PlaceType.localMarket:
        return count > 1
            ? '$count local markets nearby - Very busy, use alternate routes'
            : 'Local market nearby - Peak: 6-10 AM & 5-8 PM';
      case PlaceType.vendor:
      case PlaceType.foodStall:
        return count > 2
            ? '$count street vendors nearby - Narrow lanes, slow traffic'
            : 'Street vendors nearby - Expect slow-moving traffic';
      case PlaceType.cafe:
      case PlaceType.restaurant:
        return count > 3
            ? '$count food places nearby - Busy during meal times'
            : 'Food establishments nearby - Peak: 8-10 AM, 12-2 PM, 6-9 PM';
      case PlaceType.busStation:
      case PlaceType.trainStation:
        return 'Public transport hub nearby - High traffic, plan extra time';
      case PlaceType.hospital:
        return 'Hospital nearby - Moderate traffic, emergency vehicles possible';
      case PlaceType.bakery:
        return 'Bakery nearby - Busy mornings (6-9 AM)';
      case PlaceType.pharmacy:
      case PlaceType.bank:
        return 'Essential services nearby - Moderate traffic during business hours';
      default:
        return 'Multiple local places nearby - Traffic may be affected';
    }
  }

  /// Parse place type from Google Places API types array
  PlaceType _parsePlaceType(List<dynamic> types) {
    for (final type in types) {
      final typeStr = type.toString().toLowerCase();
      if (typeStr.contains('school')) return PlaceType.school;
      if (typeStr.contains('university') || typeStr.contains('college')) {
        return PlaceType.university;
      }
      if (typeStr.contains('shopping_mall') || typeStr.contains('mall')) {
        return PlaceType.shoppingMall;
      }
      if (typeStr.contains('cafe')) return PlaceType.cafe;
      if (typeStr.contains('restaurant')) return PlaceType.restaurant;
      if (typeStr.contains('supermarket') || typeStr.contains('market')) {
        if (typeStr.contains('local') || typeStr.contains('street')) {
          return PlaceType.localMarket;
        }
        return PlaceType.market;
      }
      if (typeStr.contains('vendor') || typeStr.contains('street_food')) {
        return PlaceType.vendor;
      }
      if (typeStr.contains('food') && typeStr.contains('stall')) {
        return PlaceType.foodStall;
      }
      if (typeStr.contains('pharmacy')) return PlaceType.pharmacy;
      if (typeStr.contains('bank')) return PlaceType.bank;
      if (typeStr.contains('atm')) return PlaceType.atm;
      if (typeStr.contains('gas_station') || typeStr.contains('fuel')) {
        return PlaceType.gasStation;
      }
      if (typeStr.contains('post_office')) return PlaceType.postOffice;
      if (typeStr.contains('laundry')) return PlaceType.laundry;
      if (typeStr.contains('beauty_salon') || typeStr.contains('hair')) {
        return PlaceType.beautySalon;
      }
      if (typeStr.contains('bakery')) return PlaceType.bakery;
      if (typeStr.contains('store') || typeStr.contains('shop')) {
        return PlaceType.store;
      }
      if (typeStr.contains('hospital')) return PlaceType.hospital;
      if (typeStr.contains('parking')) return PlaceType.parking;
      if (typeStr.contains('bus_station') || typeStr.contains('bus_stop')) {
        return PlaceType.busStation;
      }
      if (typeStr.contains('train_station') || typeStr.contains('subway_station')) {
        return PlaceType.trainStation;
      }
    }
    return PlaceType.other;
  }

  /// Calculate distance between two points in meters using Haversine formula
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
}

