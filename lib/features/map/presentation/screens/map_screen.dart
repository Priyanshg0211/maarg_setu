import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

import '../../../../core/constants/map_constants.dart';
import '../../services/location_service.dart';
import '../../services/directions_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/traffic_service.dart';
import '../../../../features/auth/services/auth_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _controller = Completer();
  final LocationService _locationService = LocationService();
  final DirectionsService _directionsService = DirectionsService();
  final GeocodingService _geocodingService = GeocodingService();
  final TrafficService _trafficService = TrafficService();
  final AuthService _authService = AuthService();
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();

  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;
  LatLng? _dropLocation;
  LatLng? _snappedCurrentLocation;
  LatLng? _snappedDropLocation;
  bool _isLoadingRoute = false;
  bool _isSnappingLocation = false;
  List<Map<String, dynamic>> _searchSuggestions = [];
  bool _isSearching = false;
  Timer? _searchDebounceTimer;
  RouteDetails? _routeDetails;
  List<RouteDetails> _alternativeRoutes = [];
  int _selectedRouteIndex = 0;
  bool _isNavigating = false;
  int _currentStepIndex = 0;
  bool _showAlternatives = false;
  String? _dropLocationAddress;
  
  // Real-time distance and ETA
  double? _realTimeDistance; // in meters
// in seconds
  String _formattedDistance = '';
  String _formattedETA = '';

  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};
  final Set<Polygon> _polygons = {}; // For route polygon visualization
  
  // Traffic heatmap data
  List<TrafficDataPoint> _trafficDataPoints = [];
  bool _showTrafficHeatmap = true; // Always show heatmap
  bool _isLoadingTraffic = false;
  Timer? _trafficUpdateTimer;
  LatLng? _lastTrafficUpdateLocation;
  LatLng? _heatmapCenter; // Center point for heatmap (user location or tapped location)
  
  AnimationController? _markerAnimationController;
  LatLng? _previousLocation;
  
  // Cache for arrow icon to avoid recreating it frequently
  BitmapDescriptor? _cachedArrowIcon;
  double? _cachedArrowBearing;

  @override
  void initState() {
    super.initState();
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _initLocationUpdates();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    _markerAnimationController?.dispose();
    _searchDebounceTimer?.cancel();
    _routeUpdateTimer?.cancel();
    _trafficUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocationUpdates() async {
    try {
      final hasAccess = await _locationService.canAccessLocation();
      if (!hasAccess) {
        _showSnackBar('Location access is unavailable');
        return;
      }

      final locationData = await _locationService.getCurrentLocation();
      await _handleLocationUpdate(locationData, isInitial: true);

      _locationSubscription?.cancel();
      _locationSubscription = _locationService.locationStream().listen(
        (newLocation) => _handleLocationUpdate(newLocation, moveCamera: _isNavigating),
      );
    } catch (e) {
      _showSnackBar('Error getting location: $e');
    }
  }

  Future<void> _handleLocationUpdate(
    LocationData locationData, {
    bool moveCamera = true,
    bool isInitial = false,
  }) async {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

    final newLocation = LatLng(latitude, longitude);
    
    // Snap current location to nearest road
    if (_isNavigating || isInitial) {
      setState(() {
        _isSnappingLocation = true;
      });
      
      final snappedLocation = await _geocodingService.snapToRoad(newLocation);
      _snappedCurrentLocation = snappedLocation;
      
      setState(() {
        _isSnappingLocation = false;
        _currentLocation = locationData;
      });
      await _updateMarker(locationData, snappedLocation: snappedLocation);
      setState(() {
        _updateRadar(locationData);
      });
    } else {
      setState(() {
        _currentLocation = locationData;
      });
      await _updateMarker(locationData);
      setState(() {
        _updateRadar(locationData);
      });
    }

    // Animate marker movement
    if (_previousLocation != null && _isNavigating) {
      _animateMarkerMovement(_previousLocation!, newLocation);
    }
    _previousLocation = newLocation;

    if (moveCamera && (!_isNavigating || isInitial)) {
      await _moveCameraToLocation(locationData, snappedLocation: _snappedCurrentLocation);
    } else if (_isNavigating) {
      // Auto-pan during navigation
      await _autoPanDuringNavigation(newLocation);
    }

    // Real-time rerouting if navigating
    if (_isNavigating && _dropLocation != null) {
      _rerouteIfNeeded(newLocation);
    } else if (_dropLocation != null && !_isLoadingRoute) {
      // Always ensure route is fetched when drop location is set
      if (_routeDetails == null) {
        _fetchRoute();
      }
    }
    
    // Update real-time distance and ETA
    if (_dropLocation != null) {
      _updateRealTimeDistanceAndETA(newLocation);
    }
  }

  void _animateMarkerMovement(LatLng from, LatLng to) {
    _markerAnimationController?.reset();
    _markerAnimationController?.forward();
  }

  Future<void> _updateMarker(LocationData locationData, {LatLng? snappedLocation}) async {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

    final position = snappedLocation ?? LatLng(latitude, longitude);
    
    _markers.removeWhere((marker) => marker.markerId.value == 'currentLocation');
    
    // Calculate rotation angle - point toward drop location if available, otherwise use heading
    double rotation = locationData.heading ?? 0;
    if (_dropLocation != null) {
      final destination = _snappedDropLocation ?? _dropLocation!;
      rotation = _calculateBearing(position, destination);
    }
    
    // Create arrow icon pointing toward destination
    BitmapDescriptor icon;
    if (_dropLocation != null && !_isNavigating) {
      // Use custom arrow icon when drop location is set
      // Cache icon if bearing hasn't changed significantly (within 5 degrees)
      if (_cachedArrowIcon != null && 
          _cachedArrowBearing != null && 
          (rotation - _cachedArrowBearing!).abs() < 5) {
        icon = _cachedArrowIcon!;
      } else {
        icon = await _createArrowIcon(rotation);
        _cachedArrowIcon = icon;
        _cachedArrowBearing = rotation;
      }
    } else {
      // Use default marker during navigation or when no destination
      _cachedArrowIcon = null;
      _cachedArrowBearing = null;
      icon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueBlue,
      );
    }
    
    _markers.add(
      Marker(
        markerId: const MarkerId('currentLocation'),
        position: position,
        infoWindow: const InfoWindow(
          title: 'Your Location',
          snippet: 'You are here',
        ),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        flat: _isNavigating, // Flat marker during navigation
        rotation: rotation,
      ),
    );
  }

  /// Create a custom arrow icon pointing in the specified direction
  Future<BitmapDescriptor> _createArrowIcon(double bearing) async {
    // Create a custom painter for the arrow
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 60.0;
    
    // Center the canvas for rotation
    canvas.translate(size / 2, size / 2);
    canvas.rotate((bearing - 90) * math.pi / 180); // Rotate to point in bearing direction
    canvas.translate(-size / 2, -size / 2);
    
    // Draw arrow pointing upward (will be rotated by bearing)
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    // Arrow shape: triangle pointing up
    final path = Path();
    path.moveTo(size / 2, 0); // Top point (arrow tip)
    path.lineTo(size, size * 0.8); // Bottom right
    path.lineTo(size * 0.6, size * 0.8); // Inner right
    path.lineTo(size * 0.6, size); // Bottom right inner
    path.lineTo(size * 0.4, size); // Bottom left inner
    path.lineTo(size * 0.4, size * 0.8); // Inner left
    path.lineTo(0, size * 0.8); // Bottom left
    path.close();
    
    // Draw arrow
    canvas.drawPath(path, paint);
    canvas.drawPath(path, strokePaint);
    
    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _addDropLocationMarker(LatLng position, {bool isDragging = false}) async {
    // Snap to road
    if (!isDragging) {
      setState(() {
        _isSnappingLocation = true;
      });
      
      final snapped = await _geocodingService.snapToRoad(position);
      _snappedDropLocation = snapped;
      position = snapped!;
      
      // Reverse geocode to get address
      final addressInfo = await _geocodingService.reverseGeocode(position);
      _dropLocationAddress = addressInfo?['address'] as String?;
      
      setState(() {
        _isSnappingLocation = false;
      });
    }
    
    _markers.removeWhere((marker) => marker.markerId.value == 'dropLocation');
    
    _markers.add(
      Marker(
        markerId: const MarkerId('dropLocation'),
        position: position,
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: _dropLocationAddress ?? 'Tap to remove',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
        anchor: const Offset(0.5, 1.0),
        draggable: true,
        onTap: () {
          _showRemoveDestinationDialog();
        },
        onDragEnd: (newPosition) async {
          // Snap to road when dragging ends
          setState(() {
            _isSnappingLocation = true;
          });
          
          final snapped = await _geocodingService.snapToRoad(newPosition);
          _snappedDropLocation = snapped;
          
          // Reverse geocode to get address
          final addressInfo = await _geocodingService.reverseGeocode(snapped!);
          _dropLocationAddress = addressInfo?['address'] as String?;
          
          setState(() {
            _dropLocation = snapped;
            _isSnappingLocation = false;
          });
          
          await _addDropLocationMarker(snapped, isDragging: false);
          _fetchRoute(showAlternatives: true);
          
          // Update marker to show arrow pointing to drop location
          if (_currentLocation != null) {
            await _updateMarker(_currentLocation!);
          }
        },
      ),
    );
  }

  void _removeDropLocation() {
    setState(() {
      _dropLocation = null;
      _snappedDropLocation = null;
      _routeDetails = null;
      _alternativeRoutes = [];
      _isNavigating = false;
      _currentStepIndex = 0;
      _destinationController.clear();
      _dropLocationAddress = null;
      _markers.removeWhere((marker) => marker.markerId.value == 'dropLocation');
      _polylines.clear();
      _polygons.clear();
      _searchSuggestions = [];
      _realTimeDistance = null;
      _formattedDistance = '';
      _formattedETA = '';
    });
    
    // Reset heatmap to user location when drop location is removed
    if (_currentLocation != null) {
      final lat = _currentLocation!.latitude;
      final lng = _currentLocation!.longitude;
      if (lat != null && lng != null) {
        setState(() {
          _heatmapCenter = LatLng(lat, lng);
        });
        _updateTrafficHeatmap(LatLng(lat, lng));
      }
    }
    
    // Update marker to remove arrow when drop location is removed
    if (_currentLocation != null) {
      _updateMarker(_currentLocation!);
    }
  }

  Future<void> _fetchRoute({bool showAlternatives = false}) async {
    final origin = _snappedCurrentLocation ?? 
        (_currentLocation != null 
            ? LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!)
            : null);
    final destination = _snappedDropLocation ?? _dropLocation;
    
    if (origin == null || destination == null) return;

    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final routes = await _directionsService.getRoutes(
        origin: origin,
        destination: destination,
        alternatives: showAlternatives,
      );

      setState(() {
        _polylines.clear();
        if (routes.isNotEmpty) {
          _alternativeRoutes = routes;
          _selectedRouteIndex = 0;
          _routeDetails = routes[0];
          _updateRoutePolylines(); // This will display the path with enhanced styling
          
          // Update real-time distance and ETA with route data
          if (_currentLocation != null) {
            final currentLat = _currentLocation!.latitude;
            final currentLng = _currentLocation!.longitude;
            if (currentLat != null && currentLng != null) {
              _updateRealTimeDistanceAndETA(LatLng(currentLat, currentLng));
            }
          }
        } else {
          // If no routes returned, show error message
          _showSnackBar('No route found. Please try again or select a different destination.');
        }
        _isLoadingRoute = false;
      });
      
      // Show success message when route is found
      if (routes.isNotEmpty) {
        _showSnackBar('Route found! Path displayed on map.');
      }
    } catch (e) {
      setState(() {
        _isLoadingRoute = false;
      });
      _showSnackBar('Error fetching route: $e. Please check your internet connection and try again.');
    }
  }


  void _updateRoutePolylines() {
    _polylines.clear();
    _polygons.clear();
    
    for (int i = 0; i < _alternativeRoutes.length; i++) {
      final route = _alternativeRoutes[i];
      final isSelected = i == _selectedRouteIndex;
      
      // Add polyline for the route path with Google Maps-like styling
      _polylines.add(
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: route.points,
          color: isSelected 
              ? const Color(0xFF4285F4) // Google Maps blue for selected route
              : Colors.grey.withOpacity(0.4), // Lighter grey for alternatives
          width: isSelected ? 8 : 5, // Thicker line for selected route
          patterns: isSelected ? [] : [PatternItem.dash(20), PatternItem.gap(10)], // Dashed for alternatives
          geodesic: true,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
          zIndex: isSelected ? 2 : 1, // Selected route on top
        ),
      );
      
      // Add a subtle shadow/outline for the selected route (Google Maps style)
      if (isSelected && route.points.length >= 2) {
        _polylines.add(
          Polyline(
            polylineId: PolylineId('route_${i}_outline'),
            points: route.points,
            color: Colors.white.withOpacity(0.8),
            width: 12, // Slightly wider for outline effect
            patterns: [],
            geodesic: true,
            jointType: JointType.round,
            endCap: Cap.roundCap,
            startCap: Cap.roundCap,
            zIndex: 0, // Behind the main route
          ),
        );
      }
      
      // Add polygon around the route for visualization (only for selected route)
      if (isSelected && route.points.length >= 2) {
        final routePolygon = _createRoutePolygon(route.points);
        if (routePolygon.isNotEmpty) {
          _polygons.add(
            Polygon(
              polygonId: PolygonId('route_polygon_$i'),
              points: routePolygon,
              fillColor: const Color(0xFF4285F4).withOpacity(0.1), // Subtle fill
              strokeColor: Colors.transparent,
              strokeWidth: 0,
              geodesic: true,
            ),
          );
        }
      }
    }
  }

  /// Create a polygon around the route path by creating a buffer zone
  List<LatLng> _createRoutePolygon(List<LatLng> routePoints) {
    if (routePoints.length < 2) return [];
    
    // Simplified polygon creation - create a buffer around the route
    // For better performance, we'll create a simpler polygon using route bounds
    if (routePoints.length < 10) {
      // For short routes, create a simple buffer
      return _createSimpleRouteBuffer(routePoints);
    }
    
    // For longer routes, sample points to reduce complexity
    List<LatLng> sampledPoints = [];
    final step = (routePoints.length / 50).ceil(); // Sample every Nth point
    for (int i = 0; i < routePoints.length; i += step) {
      sampledPoints.add(routePoints[i]);
    }
    if (sampledPoints.last != routePoints.last) {
      sampledPoints.add(routePoints.last);
    }
    
    return _createSimpleRouteBuffer(sampledPoints);
  }

  /// Create a simple buffer polygon around route points
  List<LatLng> _createSimpleRouteBuffer(List<LatLng> routePoints) {
    if (routePoints.length < 2) return [];
    
    List<LatLng> leftSide = [];
    List<LatLng> rightSide = [];
    const double bufferDistance = 0.00015; // Approximately 15-20 meters buffer
    
    for (int i = 0; i < routePoints.length; i++) {
      LatLng point = routePoints[i];
      double bearing = 0;
      
      if (i < routePoints.length - 1) {
        bearing = _calculateBearing(point, routePoints[i + 1]);
      } else if (i > 0) {
        bearing = _calculateBearing(routePoints[i - 1], point);
      }
      
      // Calculate perpendicular points
      final leftBearing = (bearing + 90) % 360;
      final rightBearing = (bearing - 90 + 360) % 360;
      
      leftSide.add(_calculateOffset(point, bufferDistance, leftBearing));
      rightSide.insert(0, _calculateOffset(point, bufferDistance, rightBearing));
    }
    
    // Combine left and right sides to form closed polygon
    return [...leftSide, ...rightSide, leftSide.first];
  }

  /// Calculate bearing between two points
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - 
              math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    
    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  /// Calculate offset point from a given point
  LatLng _calculateOffset(LatLng point, double distance, double bearing) {
    const double earthRadius = 6371000; // meters
    final lat1 = point.latitude * math.pi / 180;
    final lon1 = point.longitude * math.pi / 180;
    final bearingRad = bearing * math.pi / 180;
    
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(distance / earthRadius) +
      math.cos(lat1) * math.sin(distance / earthRadius) * math.cos(bearingRad),
    );
    
    final lon2 = lon1 + math.atan2(
      math.sin(bearingRad) * math.sin(distance / earthRadius) * math.cos(lat1),
      math.cos(distance / earthRadius) - math.sin(lat1) * math.sin(lat2),
    );
    
    return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  void _selectRoute(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _routeDetails = _alternativeRoutes[index];
      _currentStepIndex = 0;
      _updateRoutePolylines();
      
      // Update real-time distance and ETA with selected route
      if (_currentLocation != null) {
        final currentLat = _currentLocation!.latitude;
        final currentLng = _currentLocation!.longitude;
        if (currentLat != null && currentLng != null) {
          _updateRealTimeDistanceAndETA(LatLng(currentLat, currentLng));
        }
      }
    });
  }

  Future<void> _onMapTap(LatLng position) async {
    setState(() {
      _dropLocation = position;
      _destinationController.clear();
      // Update heatmap center to tapped location
      _heatmapCenter = position;
    });
    
    // Update heatmap at tapped location
    _updateTrafficHeatmap(position);
    
    await _addDropLocationMarker(position);
    
    // Automatically fetch and display the route path
    await _fetchRoute(showAlternatives: true);
    
    // Update marker to show arrow pointing to drop location
    if (_currentLocation != null) {
      await _updateMarker(_currentLocation!);
    }
    
    // Update real-time distance and ETA
    if (_currentLocation != null) {
      final currentLat = _currentLocation!.latitude;
      final currentLng = _currentLocation!.longitude;
      if (currentLat != null && currentLng != null) {
        _updateRealTimeDistanceAndETA(LatLng(currentLat, currentLng));
      }
    }
    
    // Smoothly animate camera to show the full path
    await _animateToShowPath();
  }

  /// Handle search text changes with debouncing
  /// Following Google Maps search pattern
  void _onSearchChanged(String query) {
    // Cancel previous timer
    _searchDebounceTimer?.cancel();
    
    final trimmedQuery = query.trim();
    
    if (trimmedQuery.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    // Require at least 2 characters to search (reduces API calls)
    if (trimmedQuery.length < 2) {
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    // Set loading state
    setState(() {
      _isSearching = true;
      _searchSuggestions = []; // Clear previous results while searching
    });

    // Debounce search - wait 400ms after user stops typing (Google Maps-like)
    _searchDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(trimmedQuery);
    });
  }

  /// Perform the actual search using Places API
  /// Following the pattern: getSuggestion() from the sample code
  Future<void> _performSearch(String query) async {
    if (query.isEmpty || query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _searchSuggestions = [];
          _isSearching = false;
        });
      }
      return;
    }

    try {
      // Get current location for location bias (better results like Google Maps)
      LatLng? currentLocation;
      if (_currentLocation != null) {
        currentLocation = LatLng(
          _currentLocation!.latitude!,
          _currentLocation!.longitude!,
        );
      }
      
      // Call Places API autocomplete
      final suggestions = await _geocodingService.searchPlaces(
        query,
        location: currentLocation,
        radius: 50000, // 50km radius for location bias
      );
      
      // Only update if the query hasn't changed and widget is still mounted
      if (mounted && _destinationController.text.trim() == query) {
        setState(() {
          _searchSuggestions = suggestions;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Error performing search: $e');
      if (mounted) {
        setState(() {
          _searchSuggestions = [];
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _setDestinationFromAddress(String address) async {
    setState(() {
      _isLoadingRoute = true;
      _destinationController.text = address;
      _destinationFocusNode.unfocus();
      _searchSuggestions = [];
    });

    try {
      final location = await _geocodingService.geocodeAddress(address);
      if (location != null) {
        // Immediately show the location on map
        setState(() {
          _dropLocation = location;
          _dropLocationAddress = address;
        });
        
        // Add a temporary preview marker first
        _markers.removeWhere((marker) => marker.markerId.value == 'dropLocation');
        _markers.add(
          Marker(
            markerId: const MarkerId('dropLocation'),
            position: location,
            infoWindow: InfoWindow(
              title: 'Destination',
              snippet: address,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            anchor: const Offset(0.5, 1.0),
          ),
        );
        
        // Center camera on the selected location
        final controller = await _controller.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: location,
              zoom: 16.0,
            ),
          ),
        );
        
        // Now snap to road and update marker
        await _addDropLocationMarker(location);
        
        // Automatically fetch and display the route path
        await _fetchRoute(showAlternatives: true);
        
        // Update marker to show arrow pointing to drop location
        if (_currentLocation != null) {
          await _updateMarker(_currentLocation!);
        }
        
        // Update real-time distance and ETA
        if (_currentLocation != null) {
          final currentLat = _currentLocation!.latitude;
          final currentLng = _currentLocation!.longitude;
          if (currentLat != null && currentLng != null) {
            _updateRealTimeDistanceAndETA(LatLng(currentLat, currentLng));
          }
        }
        
        // Smoothly animate camera to show the full path
        await _animateToShowPath();
      } else {
        _showSnackBar('Could not find the address. Please try again.');
        setState(() {
          _isLoadingRoute = false;
        });
      }
    } catch (e) {
      _showSnackBar('Error finding address: $e');
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  Future<void> _setDestinationFromPlaceId(String placeId, String description) async {
    // Cancel any pending search
    _searchDebounceTimer?.cancel();
    
    setState(() {
      _isLoadingRoute = true;
      _destinationController.text = description;
      _destinationFocusNode.unfocus();
      _searchSuggestions = [];
      _isSearching = false;
    });

    try {
      final placeDetails = await _geocodingService.getPlaceDetails(placeId);
      if (placeDetails != null) {
        final location = placeDetails['location'] as LatLng;
        final address = placeDetails['address'] as String? ?? description;
        
        // Immediately show the location on map (like Google Maps)
        setState(() {
          _dropLocation = location;
          _dropLocationAddress = address;
        });
        
        // Add a temporary preview marker first
        _markers.removeWhere((marker) => marker.markerId.value == 'dropLocation');
        _markers.add(
          Marker(
            markerId: const MarkerId('dropLocation'),
            position: location,
            infoWindow: InfoWindow(
              title: placeDetails['name'] as String? ?? 'Destination',
              snippet: address,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            anchor: const Offset(0.5, 1.0),
          ),
        );
        
        // Center camera on the selected location
        final controller = await _controller.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: location,
              zoom: 16.0, // Good zoom level to see the location
            ),
          ),
        );
        
        // Now snap to road and update marker
        await _addDropLocationMarker(location);
        
        // Automatically fetch and display the route path
        await _fetchRoute(showAlternatives: true);
        
        // Update marker to show arrow pointing to drop location
        if (_currentLocation != null) {
          await _updateMarker(_currentLocation!);
        }
        
        // Update real-time distance and ETA
        if (_currentLocation != null) {
          final currentLat = _currentLocation!.latitude;
          final currentLng = _currentLocation!.longitude;
          if (currentLat != null && currentLng != null) {
            _updateRealTimeDistanceAndETA(LatLng(currentLat, currentLng));
          }
        }
        
        // Smoothly animate camera to show the full path
        await _animateToShowPath();
      } else {
        _showSnackBar('Could not find the place. Please try again.');
        setState(() {
          _isLoadingRoute = false;
        });
      }
    } catch (e) {
      _showSnackBar('Error finding place: $e');
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  void _updateRadar(LocationData locationData) {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

      final location = LatLng(latitude, longitude);
      
    // Initialize heatmap center to user location if not set
    if (_heatmapCenter == null) {
      _heatmapCenter = location;
      // Fetch initial traffic data
      _updateTrafficHeatmap(location);
    }

    _circles
      ..removeWhere((circle) => circle.circleId.value == 'radar')
      ..add(
        Circle(
          circleId: const CircleId('radar'),
          center: location,
          radius: MapConstants.radarRadius,
          fillColor: Colors.blue.withOpacity(0.1),
          strokeColor: Colors.blue.withOpacity(0.3),
          strokeWidth: 1,
        ),
      );
    
    // Always update traffic heatmap when location changes (if center is user location)
    // Only auto-update if heatmap center matches user location (not when user tapped elsewhere)
    if (_showTrafficHeatmap && _heatmapCenter != null) {
      final heatmapLat = _heatmapCenter!.latitude;
      final heatmapLng = _heatmapCenter!.longitude;
      // Check if heatmap center is close to user location (within 50m)
      final distance = _calculateDistance(_heatmapCenter!, location);
      if (distance < 50) {
        // Update heatmap center to follow user location
        setState(() {
          _heatmapCenter = location;
        });
        _updateTrafficHeatmap(location);
      }
    }
  }

  /// Update traffic heatmap within 2km range
  /// Uses debouncing to avoid excessive API calls
  void _updateTrafficHeatmap(LatLng center) {
    // Cancel previous timer
    _trafficUpdateTimer?.cancel();
    
    // Check if location has changed significantly (more than 200m)
    if (_lastTrafficUpdateLocation != null) {
      final distance = _calculateDistance(_lastTrafficUpdateLocation!, center);
      if (distance < 200) {
        // Location hasn't changed much, skip update
        return;
      }
    }
    
    // Debounce: wait 2 seconds after location stops changing
    _trafficUpdateTimer = Timer(const Duration(seconds: 2), () {
      _fetchTrafficData(center);
    });
  }
  
  /// Actually fetch traffic data
  Future<void> _fetchTrafficData(LatLng center) async {
    if (_isLoadingTraffic || !_showTrafficHeatmap) return;
    
    setState(() {
      _isLoadingTraffic = true;
      _lastTrafficUpdateLocation = center;
    });

    try {
      // Get traffic data within 2km radius
      final trafficPoints = await _trafficService.getTrafficDataInRadius(
        center: center,
        radiusMeters: MapConstants.radarRadius,
      );

      if (mounted) {
        setState(() {
          _trafficDataPoints = trafficPoints;
          _isLoadingTraffic = false;
        });

        // Update circles for traffic heatmap visualization
        _updateTrafficCircles();
      }
    } catch (e) {
      print('Error updating traffic heatmap: $e');
      if (mounted) {
        setState(() {
          _isLoadingTraffic = false;
        });
      }
    }
  }

  /// Update circles to show enhanced gradient-based traffic heatmap
  void _updateTrafficCircles() {
    // Remove existing traffic heatmap circles and traffic point circles (but keep radar circle)
    _circles.removeWhere((circle) => 
      circle.circleId.value.startsWith('traffic_heatmap') || 
      circle.circleId.value.startsWith('traffic_point_'));
    
    if (!_showTrafficHeatmap || _heatmapCenter == null) {
      setState(() {});
      return;
    }

    // If we have traffic data points, create a sophisticated gradient heatmap
    if (_trafficDataPoints.isNotEmpty) {
      // Calculate average traffic intensity from all traffic points
      final avgIntensity = _getAverageTrafficIntensity();
      if (avgIntensity == null) {
        setState(() {});
        return;
      }

      // Get base color based on average intensity
      final baseColor = _getTrafficColorForIntensity(avgIntensity);
      
      // Create multiple concentric circles with gradient effect for better visualization
      // Outer circle (largest, most transparent)
      _circles.add(
        Circle(
          circleId: const CircleId('traffic_heatmap_outer'),
          center: _heatmapCenter!,
          radius: MapConstants.radarRadius,
          fillColor: baseColor.withOpacity(0.15),
          strokeColor: baseColor.withOpacity(0.4),
          strokeWidth: 2,
          zIndex: 0,
        ),
      );
      
      // Middle circle
      _circles.add(
        Circle(
          circleId: const CircleId('traffic_heatmap_middle'),
          center: _heatmapCenter!,
          radius: MapConstants.radarRadius * 0.7,
          fillColor: baseColor.withOpacity(0.25),
          strokeColor: baseColor.withOpacity(0.5),
          strokeWidth: 2,
          zIndex: 0,
        ),
      );
      
      // Inner circle (most intense)
      _circles.add(
        Circle(
          circleId: const CircleId('traffic_heatmap_inner'),
          center: _heatmapCenter!,
          radius: MapConstants.radarRadius * 0.4,
          fillColor: baseColor.withOpacity(0.35),
          strokeColor: baseColor.withOpacity(0.7),
          strokeWidth: 3,
          zIndex: 0,
        ),
      );
      
      // Add individual traffic point circles for more granular visualization
      for (int i = 0; i < _trafficDataPoints.length; i++) {
        final point = _trafficDataPoints[i];
        final pointColor = _getTrafficColorForIntensity(point.intensity);
        final distance = _calculateDistance(_heatmapCenter!, point.location);
        
        // Only show points within the radar radius
        if (distance <= MapConstants.radarRadius) {
          // Size based on intensity (more intense = larger circle)
          final radius = 50.0 + (point.intensity.index * 30.0);
          final opacity = 0.4 + (point.intensity.index * 0.1);
          
          _circles.add(
            Circle(
              circleId: CircleId('traffic_point_$i'),
              center: point.location,
              radius: radius,
              fillColor: pointColor.withOpacity(opacity.clamp(0.3, 0.6)),
              strokeColor: pointColor.withOpacity(0.8),
              strokeWidth: 1,
              zIndex: 1,
            ),
          );
        }
      }
    } else {
      // Show a subtle default circle when no data yet
      _circles.add(
        Circle(
          circleId: const CircleId('traffic_heatmap_default'),
          center: _heatmapCenter!,
          radius: MapConstants.radarRadius,
          fillColor: Colors.grey.withOpacity(0.1),
          strokeColor: Colors.grey.withOpacity(0.3),
          strokeWidth: 2,
          zIndex: 0,
        ),
      );
    }
    
    setState(() {});
  }
  
  /// Get traffic color for intensity (without opacity, we'll add it per circle)
  Color _getTrafficColorForIntensity(TrafficIntensity intensity) {
    switch (intensity) {
      case TrafficIntensity.none:
        return Colors.green;
      case TrafficIntensity.light:
        return Colors.yellow;
      case TrafficIntensity.moderate:
        return Colors.orange;
      case TrafficIntensity.heavy:
        return Colors.red;
      case TrafficIntensity.severe:
        return const Color(0xFF8B0000); // Dark red
    }
  }
  
  /// Reset heatmap to user location
  void _resetHeatmapToUserLocation() {
    if (_currentLocation != null) {
      final lat = _currentLocation!.latitude;
      final lng = _currentLocation!.longitude;
      if (lat != null && lng != null) {
        setState(() {
          _heatmapCenter = LatLng(lat, lng);
        });
        _updateTrafficHeatmap(LatLng(lat, lng));
      }
    }
  }
  
  /// Get average traffic intensity in the area
  TrafficIntensity? _getAverageTrafficIntensity() {
    if (_trafficDataPoints.isEmpty) return null;
    
    int totalIntensity = 0;
    for (final point in _trafficDataPoints) {
      totalIntensity += point.intensity.index;
    }
    
    final avgIndex = (totalIntensity / _trafficDataPoints.length).round();
    return TrafficIntensity.values[avgIndex.clamp(0, TrafficIntensity.values.length - 1)];
  }
  
  /// Get traffic status text
  String _getTrafficStatusText() {
    final intensity = _getAverageTrafficIntensity();
    if (intensity == null) return 'No Data';
    
    switch (intensity) {
      case TrafficIntensity.none:
        return 'Clear';
      case TrafficIntensity.light:
        return 'Light';
      case TrafficIntensity.moderate:
        return 'Moderate';
      case TrafficIntensity.heavy:
        return 'Heavy';
      case TrafficIntensity.severe:
        return 'Severe';
    }
  }

  Future<void> _moveCameraToLocation(
    LocationData locationData, {
    LatLng? snappedLocation,
  }) async {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

    final position = snappedLocation ?? LatLng(latitude, longitude);
    final controller = await _controller.future;
    
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: MapConstants.defaultZoom,
          bearing: locationData.heading?.toDouble() ?? 0,
        ),
      ),
    );
  }

  Future<void> _autoPanDuringNavigation(LatLng location) async {
    final controller = await _controller.future;
    final currentPosition = await controller.getVisibleRegion();
    
    // Check if location is within visible region
    final isVisible = _isLocationVisible(location, currentPosition);
    
    if (!isVisible) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: location,
            zoom: 17.0, // Closer zoom during navigation
            bearing: _currentLocation?.heading?.toDouble() ?? 0,
            tilt: 45.0, // Slight tilt for better navigation view
          ),
        ),
      );
    }
  }

  bool _isLocationVisible(LatLng location, LatLngBounds bounds) {
    return location.latitude >= bounds.southwest.latitude &&
        location.latitude <= bounds.northeast.latitude &&
        location.longitude >= bounds.southwest.longitude &&
        location.longitude <= bounds.northeast.longitude;
  }

  Future<void> _fitRoute() async {
    if (_currentLocation == null || _dropLocation == null) return;

    final currentLat = _currentLocation!.latitude;
    final currentLng = _currentLocation!.longitude;
    if (currentLat == null || currentLng == null) return;

    final controller = await _controller.future;
    
    final origin = _snappedCurrentLocation ?? LatLng(currentLat, currentLng);
    final destination = _snappedDropLocation ?? _dropLocation!;
    
    // If we have route points, use them for better bounds calculation
    if (_routeDetails != null && _routeDetails!.points.isNotEmpty) {
      double minLat = _routeDetails!.points[0].latitude;
      double maxLat = _routeDetails!.points[0].latitude;
      double minLng = _routeDetails!.points[0].longitude;
      double maxLng = _routeDetails!.points[0].longitude;
      
      for (final point in _routeDetails!.points) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }
      
      // Include origin and destination
      minLat = math.min(minLat, math.min(origin.latitude, destination.latitude));
      maxLat = math.max(maxLat, math.max(origin.latitude, destination.latitude));
      minLng = math.min(minLng, math.min(origin.longitude, destination.longitude));
      maxLng = math.max(maxLng, math.max(origin.longitude, destination.longitude));
      
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          120, // Padding to ensure route is fully visible
        ),
      );
    } else {
      // Fallback to simple bounds
      final southwest = LatLng(
        origin.latitude < destination.latitude ? origin.latitude : destination.latitude,
        origin.longitude < destination.longitude ? origin.longitude : destination.longitude,
      );
      final northeast = LatLng(
        origin.latitude > destination.latitude ? origin.latitude : destination.latitude,
        origin.longitude > destination.longitude ? origin.longitude : destination.longitude,
      );

      final bounds = LatLngBounds(southwest: southwest, northeast: northeast);
      
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          120,
        ),
      );
    }
  }

  /// Animate camera to smoothly show the full path when drop location is selected
  Future<void> _animateToShowPath() async {
    if (_currentLocation == null || _dropLocation == null) return;
    
    // Wait a bit for route to be fetched
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Fit the route to show the full path
    await _fitRoute();
  }

  void _rerouteIfNeeded(LatLng currentLocation) {
    if (_routeDetails == null || _routeDetails!.points.isEmpty) return;
    
    // Update current step based on proximity
    _updateCurrentStep(currentLocation);
    
    // Check if user has deviated significantly from route
    final nearestPoint = _findNearestPointOnRoute(currentLocation, _routeDetails!.points);
    final distance = _calculateDistance(currentLocation, nearestPoint);
    
    // If deviated more than 50 meters, reroute (real-time route update)
    if (distance > 50) {
      _fetchRoute(showAlternatives: false);
    }
    
    // Also update route periodically (every 30 seconds) for live traffic updates
    // This ensures we get the latest route with current traffic conditions
    _updateRoutePeriodically();
  }

  Timer? _routeUpdateTimer;
  
  void _updateRoutePeriodically() {
    // Cancel previous timer
    _routeUpdateTimer?.cancel();
    
    // Set up periodic route updates every 30 seconds during navigation
    // This fetches fresh routes with current traffic conditions
    _routeUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isNavigating && _dropLocation != null && !_isLoadingRoute) {
        _fetchRoute(showAlternatives: false);
      } else {
        // Stop timer if navigation stopped
        timer.cancel();
      }
    });
  }

  void _updateCurrentStep(LatLng currentLocation) {
    if (_routeDetails == null || _routeDetails!.steps.isEmpty) return;
    
    // Find the nearest step
    int nearestStepIndex = 0;
    double minDistance = double.infinity;
    
    for (int i = 0; i < _routeDetails!.steps.length; i++) {
      final step = _routeDetails!.steps[i];
      final distance = _calculateDistance(currentLocation, step.location);
      if (distance < minDistance) {
        minDistance = distance;
        nearestStepIndex = i;
      }
    }
    
    // Update step if we've moved to a new step (with some threshold)
    if (nearestStepIndex > _currentStepIndex && minDistance < 100) {
      setState(() {
        _currentStepIndex = nearestStepIndex;
      });
    }
  }

  LatLng _findNearestPointOnRoute(LatLng point, List<LatLng> routePoints) {
    double minDistance = double.infinity;
    LatLng nearestPoint = routePoints[0];
    
    for (var routePoint in routePoints) {
      final distance = _calculateDistance(point, routePoint);
      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = routePoint;
      }
    }
    
    return nearestPoint;
  }

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

  /// Update real-time distance and ETA between current location and drop location
  void _updateRealTimeDistanceAndETA(LatLng currentLocation) {
    if (_dropLocation == null) {
      setState(() {
        _realTimeDistance = null;
        _formattedDistance = '';
        _formattedETA = '';
      });
      return;
    }

    final destination = _snappedDropLocation ?? _dropLocation!;
    
    // Calculate straight-line distance
    final straightDistance = _calculateDistance(currentLocation, destination);
    
    // If we have route details, use route-based distance and ETA
    if (_routeDetails != null) {
      // Calculate remaining distance along the route
      final remainingDistance = _calculateRemainingRouteDistance(currentLocation);
      final remainingETA = _calculateRemainingRouteETA(remainingDistance);
      
      setState(() {
        _realTimeDistance = remainingDistance;
        _formattedDistance = _formatDistance(remainingDistance);
        _formattedETA = _formatDuration(remainingETA);
      });
    } else {
      // Use straight-line distance and estimate ETA based on average speed
      // Average driving speed: ~50 km/h = ~13.9 m/s
      const double averageSpeedMetersPerSecond = 13.9;
      final estimatedETA = (straightDistance / averageSpeedMetersPerSecond).round();
      
      setState(() {
        _realTimeDistance = straightDistance;
        _formattedDistance = _formatDistance(straightDistance);
        _formattedETA = _formatDuration(estimatedETA);
      });
    }
  }

  /// Calculate remaining distance along the route from current location
  double _calculateRemainingRouteDistance(LatLng currentLocation) {
    if (_routeDetails == null || _routeDetails!.points.isEmpty) {
      return _realTimeDistance ?? 0;
    }

    // Find the nearest point on the route and its index
    double minDistance = double.infinity;
    int nearestIndex = 0;
    
    for (int i = 0; i < _routeDetails!.points.length; i++) {
      final distance = _calculateDistance(currentLocation, _routeDetails!.points[i]);
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    
    final nearestPoint = _routeDetails!.points[nearestIndex];
    final destination = _snappedDropLocation ?? _dropLocation!;
    
    // Calculate distance from nearest point to destination along route
    double remainingDistance = 0;
    
    // Sum distances from nearest point to destination along route
    for (int i = nearestIndex; i < _routeDetails!.points.length - 1; i++) {
      remainingDistance += _calculateDistance(
        _routeDetails!.points[i],
        _routeDetails!.points[i + 1],
      );
    }
    
    // Add distance from current location to nearest route point
    remainingDistance += _calculateDistance(currentLocation, nearestPoint);
    
    // Add distance from last route point to destination
    if (_routeDetails!.points.isNotEmpty) {
      remainingDistance += _calculateDistance(
        _routeDetails!.points.last,
        destination,
      );
    }
    
    return remainingDistance;
  }

  /// Calculate remaining ETA based on remaining distance and route speed
  int _calculateRemainingRouteETA(double remainingDistance) {
    if (_routeDetails == null || _routeDetails!.distanceValue.isEmpty) {
      // Fallback: estimate based on average speed
      const double averageSpeedMetersPerSecond = 13.9;
      return (remainingDistance / averageSpeedMetersPerSecond).round();
    }

    // Calculate average speed from route
    final totalDistance = double.tryParse(_routeDetails!.distanceValue) ?? 0;
    final totalDuration = _routeDetails!.durationValue;
    
    if (totalDistance > 0 && totalDuration > 0) {
      final averageSpeed = totalDistance / totalDuration; // meters per second
      return (remainingDistance / averageSpeed).round();
    }
    
    // Fallback: estimate based on average speed
    const double averageSpeedMetersPerSecond = 13.9;
    return (remainingDistance / averageSpeedMetersPerSecond).round();
  }

  /// Format distance for display
  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Format duration for display
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

  void _startNavigation() {
    if (_routeDetails == null) return;
    
    setState(() {
      _isNavigating = true;
      _currentStepIndex = 0;
    });
    
    // Start periodic route updates for live traffic data
    _updateRoutePeriodically();
    
    // Move camera to navigation view
    if (_currentLocation != null) {
      _moveCameraToLocation(_currentLocation!, snappedLocation: _snappedCurrentLocation);
    }
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _currentStepIndex = 0;
    });
    
    // Cancel periodic route updates when navigation stops
    _routeUpdateTimer?.cancel();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showRemoveDestinationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Destination'),
        content: const Text('Do you want to remove the destination?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeDropLocation();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  NavigationStep? get _currentStep {
    if (_routeDetails == null || _routeDetails!.steps.isEmpty) return null;
    if (_currentStepIndex >= _routeDetails!.steps.length) {
      return _routeDetails!.steps.last;
    }
    return _routeDetails!.steps[_currentStepIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentLocation != null
                  ? LatLng(
                      _currentLocation!.latitude!,
                      _currentLocation!.longitude!,
                    )
                  : MapConstants.defaultCenter,
              zoom: MapConstants.defaultZoom,
            ),
            markers: _markers,
            circles: _circles,
            polylines: _polylines,
            polygons: _polygons,
            trafficEnabled: true, // Enable Google Maps traffic layer
            myLocationEnabled: !_isNavigating, // Disable default during navigation
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
            onMapCreated: (controller) {
              _controller.complete(controller);
            },
            onTap: _isNavigating ? null : _onMapTap,
          ),
          
          // Search Bar
          if (!_isNavigating)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Sign out button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue[700],
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.logout, color: Colors.white),
                            onPressed: () async {
                              try {
                                await _authService.signOut();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error signing out: ${e.toString()}'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            tooltip: 'Sign out',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 16, right: 12),
                                child: Icon(Icons.search, color: Colors.grey),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _destinationController,
                                  focusNode: _destinationFocusNode,
                                  decoration: const InputDecoration(
                                    hintText: 'Search for places or tap on map',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  onChanged: (value) {
                                    _onSearchChanged(value);
                                  },
                                  onSubmitted: (value) {
                                    if (value.isNotEmpty) {
                                      _setDestinationFromAddress(value);
                                    }
                                  },
                                ),
                              ),
                              if (_dropLocation != null || _destinationController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () {
                                    _searchDebounceTimer?.cancel();
                                    _destinationController.clear();
                                    _removeDropLocation();
                                    setState(() {
                                      _searchSuggestions = [];
                                      _isSearching = false;
                                    });
                                  },
                                ),
                            ],
                          ),
                          // Loading indicator while searching
                          if (_isSearching)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  top: BorderSide(color: Colors.grey, width: 0.5),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Text(
                                    'Searching...',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Search suggestions list (Google Maps-like)
                          if (_searchSuggestions.isNotEmpty && !_isSearching)
                            Container(
                              constraints: const BoxConstraints(maxHeight: 300),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  top: BorderSide(color: Colors.grey, width: 0.5),
                                ),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                physics: const ClampingScrollPhysics(),
                                itemCount: _searchSuggestions.length,
                                itemBuilder: (context, index) {
                                  final suggestion = _searchSuggestions[index];
                                  final description = suggestion['description'] as String;
                                  final structuredFormatting = suggestion['structured_formatting'] as Map<String, dynamic>?;
                                  
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        _setDestinationFromPlaceId(
                                          suggestion['place_id'] as String,
                                          description,
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.location_on,
                                              color: Colors.red,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Main text (like Google Maps)
                                                  Text(
                                                    structuredFormatting != null
                                                        ? (structuredFormatting['main_text'] as String? ?? description)
                                                        : description,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                      color: Colors.black87,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  // Secondary text (like Google Maps)
                                                  if (structuredFormatting != null)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 2),
                                                      child: Text(
                                                        structuredFormatting['secondary_text'] as String? ?? '',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.grey[600],
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Real-time Distance and ETA Card
          if (_dropLocation != null && _formattedDistance.isNotEmpty && !_isNavigating)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 100, left: 16, right: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.straighten,
                                    size: 20,
                                    color: Colors.blue[700],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Distance',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formattedDistance,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey[300],
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 20,
                                    color: Colors.green[700],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ETA',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formattedETA,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Loading Indicator
          if (_isLoadingRoute || _isSnappingLocation)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 16),
                      Text('Finding route...'),
                    ],
                  ),
                ),
              ),
            ),

          // Navigation Instructions Panel (during navigation)
          if (_isNavigating && _currentStep != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getManeuverIcon(_currentStep!.maneuver),
                            color: Colors.blue,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentStep!.instruction,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Row(
                                  children: [
                                    if (_formattedDistance.isNotEmpty) ...[
                                      Text(
                                        _formattedDistance,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        ' • ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                    if (_formattedETA.isNotEmpty)
                                      Text(
                                        'ETA: $_formattedETA',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    if (_formattedDistance.isEmpty && _formattedETA.isEmpty)
                                      Text(
                                        '${_currentStep!.distance} • ${_currentStep!.duration}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _stopNavigation,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _currentStepIndex / (_routeDetails!.steps.length - 1),
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Route Info Bottom Sheet
          if (_routeDetails != null && _dropLocation != null && !_isNavigating)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Route',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Text(
                                            _routeDetails!.duration,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Text(
                                            _routeDetails!.distance,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: _removeDropLocation,
                                ),
                              ],
                            ),
                            if (_alternativeRoutes.length > 1) ...[
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    'Alternative routes:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _showAlternatives = !_showAlternatives;
                                      });
                                    },
                                    child: Text(_showAlternatives ? 'Hide' : 'Show'),
                                  ),
                                ],
                              ),
                              if (_showAlternatives) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 80,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _alternativeRoutes.length,
                                    itemBuilder: (context, index) {
                                      final route = _alternativeRoutes[index];
                                      final isSelected = index == _selectedRouteIndex;
                                      return GestureDetector(
                                        onTap: () => _selectRoute(index),
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isSelected ? Colors.blue[50] : Colors.grey[100],
                                            border: Border.all(
                                              color: isSelected ? Colors.blue : Colors.transparent,
                                              width: 2,
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                route.duration,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: isSelected ? Colors.blue : Colors.black,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                route.distance,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _startNavigation,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Text(
                                  'Start Navigation',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Traffic Heatmap Status Indicator (Always Visible)
          if (!_isNavigating && _heatmapCenter != null)
            Positioned(
              left: 16,
              bottom: _routeDetails != null ? 200 : 16,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Traffic Status Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _getAverageTrafficIntensity() != null
                              ? _getTrafficColorForIntensity(_getAverageTrafficIntensity()!)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.heat_pump_rounded,
                              size: 20,
                              color: _getAverageTrafficIntensity() != null &&
                                      _getAverageTrafficIntensity()!.index > 1
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Traffic Heatmap',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _getAverageTrafficIntensity() != null &&
                                            _getAverageTrafficIntensity()!.index > 1
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                if (_trafficDataPoints.isNotEmpty)
                                  Text(
                                    _getTrafficStatusText(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _getAverageTrafficIntensity() != null &&
                                              _getAverageTrafficIntensity()!.index > 1
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Reset to user location button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _resetHeatmapToUserLocation,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.my_location,
                                  size: 18,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Reset to My Location',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Loading indicator
                      if (_isLoadingTraffic)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // Custom Map Controls
          Positioned(
            right: 16,
            bottom: _routeDetails != null && !_isNavigating ? 200 : 16,
            child: Column(
              children: [
                if (_currentLocation != null)
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'myLocation',
                    onPressed: () => _moveCameraToLocation(
                      _currentLocation!,
                      snappedLocation: _snappedCurrentLocation,
                    ),
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.my_location, color: Colors.blue),
                  ),
                const SizedBox(height: 8),
                if (_dropLocation != null)
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'fitRoute',
                    onPressed: _fitRoute,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.fit_screen, color: Colors.green),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getManeuverIcon(String maneuver) {
    switch (maneuver.toLowerCase()) {
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-right':
        return Icons.turn_right;
      case 'turn-sharp-left':
        return Icons.turn_sharp_left;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right;
      case 'uturn-left':
      case 'uturn-right':
        return Icons.u_turn_left;
      case 'straight':
        return Icons.straight;
      case 'ramp-left':
      case 'ramp-right':
        return Icons.merge;
      default:
        return Icons.navigation;
    }
  }
}
