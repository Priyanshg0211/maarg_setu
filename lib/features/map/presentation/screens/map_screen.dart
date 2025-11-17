import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

import '../../../../core/constants/map_constants.dart';
import '../../services/location_service.dart';
import '../../services/directions_service.dart';
import '../../services/geocoding_service.dart';

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
  RouteDetails? _routeDetails;
  List<RouteDetails> _alternativeRoutes = [];
  int _selectedRouteIndex = 0;
  bool _isNavigating = false;
  int _currentStepIndex = 0;
  bool _showAlternatives = false;
  String? _dropLocationAddress;

  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};
  
  AnimationController? _markerAnimationController;
  LatLng? _previousLocation;

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
        _updateMarker(locationData, snappedLocation: snappedLocation);
        _updateRadar(locationData);
      });
    } else {
      setState(() {
        _currentLocation = locationData;
        _updateMarker(locationData);
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
      _fetchRoute();
    }
  }

  void _animateMarkerMovement(LatLng from, LatLng to) {
    _markerAnimationController?.reset();
    _markerAnimationController?.forward();
  }

  void _updateMarker(LocationData locationData, {LatLng? snappedLocation}) {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

    final position = snappedLocation ?? LatLng(latitude, longitude);
    
    _markers.removeWhere((marker) => marker.markerId.value == 'currentLocation');
    
    _markers.add(
      Marker(
        markerId: const MarkerId('currentLocation'),
        position: position,
        infoWindow: const InfoWindow(
          title: 'Your Location',
          snippet: 'You are here',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueBlue,
        ),
        anchor: const Offset(0.5, 0.5),
        flat: _isNavigating, // Flat marker during navigation
        rotation: locationData.heading ?? 0,
      ),
    );
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
      _searchSuggestions = [];
    });
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
          _updateRoutePolylines();
          _fitRoute();
        }
        _isLoadingRoute = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingRoute = false;
      });
      _showSnackBar('Error fetching route: $e');
    }
  }

  void _updateRoutePolylines() {
    _polylines.clear();
    
    for (int i = 0; i < _alternativeRoutes.length; i++) {
      final route = _alternativeRoutes[i];
      final isSelected = i == _selectedRouteIndex;
      
      _polylines.add(
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: route.points,
          color: isSelected 
              ? const Color(0xFF4285F4) // Google Maps blue
              : Colors.grey.withOpacity(0.5),
          width: isSelected ? 6 : 4,
          patterns: [],
          geodesic: true,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
        ),
      );
    }
  }

  void _selectRoute(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _routeDetails = _alternativeRoutes[index];
      _currentStepIndex = 0;
      _updateRoutePolylines();
    });
  }

  Future<void> _onMapTap(LatLng position) async {
    setState(() {
      _dropLocation = position;
      _destinationController.clear();
    });
    await _addDropLocationMarker(position);
    _fetchRoute(showAlternatives: true);
  }

  Future<void> _searchDestination(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
      });
      return;
    }

    try {
      final suggestions = await _geocodingService.searchPlaces(query);
      setState(() {
        _searchSuggestions = suggestions;
      });
    } catch (e) {
      // Silently handle errors
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
        setState(() {
          _dropLocation = location;
        });
        await _addDropLocationMarker(location);
        _fetchRoute(showAlternatives: true);
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
    setState(() {
      _isLoadingRoute = true;
      _destinationController.text = description;
      _destinationFocusNode.unfocus();
      _searchSuggestions = [];
    });

    try {
      final location = await _geocodingService.getPlaceDetails(placeId);
      if (location != null) {
        setState(() {
          _dropLocation = location;
        });
        await _addDropLocationMarker(location);
        _fetchRoute(showAlternatives: true);
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

    _circles
      ..clear()
      ..add(
        Circle(
          circleId: const CircleId('radar'),
          center: LatLng(latitude, longitude),
          radius: MapConstants.radarRadius,
          fillColor: Colors.blue.withOpacity(0.1),
          strokeColor: Colors.blue.withOpacity(0.3),
          strokeWidth: 1,
        ),
      );
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
        100,
      ),
    );
  }

  void _rerouteIfNeeded(LatLng currentLocation) {
    if (_routeDetails == null || _routeDetails!.points.isEmpty) return;
    
    // Update current step based on proximity
    _updateCurrentStep(currentLocation);
    
    // Check if user has deviated significantly from route
    final nearestPoint = _findNearestPointOnRoute(currentLocation, _routeDetails!.points);
    final distance = _calculateDistance(currentLocation, nearestPoint);
    
    // If deviated more than 50 meters, reroute
    if (distance > 50) {
      _fetchRoute(showAlternatives: false);
    }
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

  void _startNavigation() {
    if (_routeDetails == null) return;
    
    setState(() {
      _isNavigating = true;
      _currentStepIndex = 0;
    });
    
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
                                    if (value.isNotEmpty) {
                                      _searchDestination(value);
                                    } else {
                                      setState(() {
                                        _searchSuggestions = [];
                                      });
                                    }
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
                                    _destinationController.clear();
                                    _removeDropLocation();
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                          if (_searchSuggestions.isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Colors.grey, width: 0.5),
                                ),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _searchSuggestions.length,
                                itemBuilder: (context, index) {
                                  final suggestion = _searchSuggestions[index];
                                  return InkWell(
                                    onTap: () {
                                      _setDestinationFromPlaceId(
                                        suggestion['place_id'] as String,
                                        suggestion['description'] as String,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              suggestion['description'] as String,
                                              style: const TextStyle(fontSize: 14),
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
                      ),
                    ),
                  ],
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
                                Text(
                                  '${_currentStep!.distance} • ${_currentStep!.duration}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
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
