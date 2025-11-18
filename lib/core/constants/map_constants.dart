import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapConstants {
  static const LatLng defaultCenter = LatLng(21.1904494, 81.2849169);
  static const double radarRadius = 3000.0; // 3km range
  static const double defaultZoom = 15.0;
  
  // IMPORTANT: For production, move this to environment variables
  // and use proper API key restrictions in Google Cloud Console
  // Current key should have these APIs enabled:
  // 1. Maps SDK for Android
  // 2. Maps SDK for iOS
  // 3. Directions API
  // 4. Places API
  // 5. Geocoding API
  static const String googleMapsApiKey = 'AIzaSyCK7_NvFvexUKYaNeDalhmFiNHN5wcOnyI';
  
  // Gemini AI API Key (Get from https://makersuite.google.com/app/apikey)
  // TODO: Replace with your actual Gemini API key
  static const String geminiApiKey = 'AIzaSyA8Iv7qTw9FjJLg7rx_B6zl0ajyo0EkN_I';
  
  // API URLs
  static const String directionsApiUrl = 'https://maps.googleapis.com/maps/api/directions/json';
  static const String geocodingApiUrl = 'https://maps.googleapis.com/maps/api/geocode/json';
  static const String placesAutocompleteApiUrl = 'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String placeDetailsApiUrl = 'https://maps.googleapis.com/maps/api/place/details/json';
  
  // Timeout settings for API calls
  static const Duration apiTimeout = Duration(seconds: 30);
  
  // Retry settings
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
}