import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapConstants {
  static const LatLng defaultCenter = LatLng(21.1904494, 81.2849169);
  static const double radarRadius = 2500.0;
  static const double defaultZoom = 15.0;
  
  // Google Directions API - Using the same API key from AndroidManifest.xml
  static const String googleMapsApiKey = 'AIzaSyCK7_NvFvexUKYaNeDalhmFiNHN5wcOnyI';
  static const String directionsApiUrl = 'https://maps.googleapis.com/maps/api/directions/json';
}
