import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapConstants {
  static const LatLng defaultCenter = LatLng(21.1904494, 81.2849169);
  static const double radarRadius = 2500.0;
  static const double defaultZoom = 15.0;
  
  // Google Maps API Key - Used for Places API, Geocoding API, and Directions API
  static const String googleMapsApiKey = 'AIzaSyCK7_NvFvexUKYaNeDalhmFiNHN5wcOnyI';
  
  // API URLs
  static const String directionsApiUrl = 'https://maps.googleapis.com/maps/api/directions/json';
  static const String geocodingApiUrl = 'https://maps.googleapis.com/maps/api/geocode/json';
  static const String placesAutocompleteApiUrl = 'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String placeDetailsApiUrl = 'https://maps.googleapis.com/maps/api/place/details/json';
}
