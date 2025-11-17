import 'dart:async';

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

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final LocationService _locationService = LocationService();
  final DirectionsService _directionsService = DirectionsService();
  final GeocodingService _geocodingService = GeocodingService();
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();

  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;
  LatLng? _dropLocation;
  bool _isLoadingRoute = false;
  List<Map<String, dynamic>> _searchSuggestions = [];
  RouteDetails? _routeDetails;

  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _initLocationUpdates();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
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
      _handleLocationUpdate(locationData);

      _locationSubscription?.cancel();
      _locationSubscription = _locationService.locationStream().listen(
        (newLocation) => _handleLocationUpdate(newLocation, moveCamera: false),
      );
    } catch (e) {
      _showSnackBar('Error getting location: $e');
    }
  }

  void _handleLocationUpdate(
    LocationData locationData, {
    bool moveCamera = true,
  }) {
    setState(() {
      _currentLocation = locationData;
      _updateMarker(locationData);
      _updateRadar(locationData);
    });

    if (moveCamera && _dropLocation == null) {
      _moveCameraToLocation(locationData);
    }

    // Update route if drop location exists
    if (_dropLocation != null) {
      _fetchRoute();
    }
  }

  void _updateMarker(LocationData locationData) {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

    // Clear existing markers except drop location
    _markers.removeWhere((marker) => marker.markerId.value == 'currentLocation');
    
    _markers.add(
      Marker(
        markerId: const MarkerId('currentLocation'),
        position: LatLng(latitude, longitude),
        infoWindow: const InfoWindow(
          title: 'Your Location',
          snippet: 'You are here',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueBlue,
        ),
        anchor: const Offset(0.5, 0.5),
      ),
    );
  }

  void _addDropLocationMarker(LatLng position) {
    _markers.removeWhere((marker) => marker.markerId.value == 'dropLocation');
    
    _markers.add(
      Marker(
        markerId: const MarkerId('dropLocation'),
        position: position,
        infoWindow: const InfoWindow(
          title: 'Destination',
          snippet: 'Tap to remove',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
        anchor: const Offset(0.5, 1.0),
        onTap: () {
          _showRemoveDestinationDialog();
        },
      ),
    );
  }

  void _removeDropLocation() {
    setState(() {
      _dropLocation = null;
      _routeDetails = null;
      _destinationController.clear();
      _markers.removeWhere((marker) => marker.markerId.value == 'dropLocation');
      _polylines.clear();
      _searchSuggestions = [];
    });
  }

  Future<void> _fetchRoute() async {
    if (_currentLocation == null || _dropLocation == null) return;

    final currentLat = _currentLocation!.latitude;
    final currentLng = _currentLocation!.longitude;
    if (currentLat == null || currentLng == null) return;

    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final origin = LatLng(currentLat, currentLng);
      final route = await _directionsService.getRoute(
        origin: origin,
        destination: _dropLocation!,
      );

      setState(() {
        _polylines.clear();
        if (route != null && route.points.isNotEmpty) {
          _routeDetails = route;
          // Draw the detailed route path like Google Maps
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: route.points,
              color: const Color(0xFF4285F4), // Google Maps blue color
              width: 6,
              patterns: [],
              geodesic: true,
              jointType: JointType.round,
              endCap: Cap.roundCap,
              startCap: Cap.roundCap,
            ),
          );
          
          // Auto-fit route to show both locations
          _fitRoute();
        } else {
          // Fallback: draw straight line if API fails
          final fallbackPoints = _directionsService.createStraightLine(
            origin,
            _dropLocation!,
          );
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: fallbackPoints,
              color: Colors.orange.withOpacity(0.7),
              width: 4,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
              geodesic: true,
            ),
          );
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

  void _onMapTap(LatLng position) {
    setState(() {
      _dropLocation = position;
      _destinationController.clear();
      _addDropLocationMarker(position);
    });
    _fetchRoute();
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
          _addDropLocationMarker(location);
        });
        _fetchRoute();
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
          _addDropLocationMarker(location);
        });
        _fetchRoute();
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

  Future<void> _moveCameraToLocation(LocationData locationData) async {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

    final controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(latitude, longitude),
          zoom: MapConstants.defaultZoom,
        ),
      ),
    );
  }

  Future<void> _fitRoute() async {
    if (_currentLocation == null || _dropLocation == null) return;

    final currentLat = _currentLocation!.latitude;
    final currentLng = _currentLocation!.longitude;
    if (currentLat == null || currentLng == null) return;

    final controller = await _controller.future;
    
    // Create bounds that include both current location and drop location
    final southwest = LatLng(
      currentLat < _dropLocation!.latitude ? currentLat : _dropLocation!.latitude,
      currentLng < _dropLocation!.longitude ? currentLng : _dropLocation!.longitude,
    );
    final northeast = LatLng(
      currentLat > _dropLocation!.latitude ? currentLat : _dropLocation!.latitude,
      currentLng > _dropLocation!.longitude ? currentLng : _dropLocation!.longitude,
    );

    final bounds = LatLngBounds(southwest: southwest, northeast: northeast);
    
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        100, // Padding for better view
      ),
    );
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
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // We'll use custom button
            zoomControlsEnabled: false, // We'll use custom controls
            compassEnabled: true,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _controller.complete(controller);
            },
            onTap: _onMapTap,
          ),
          
          // Modern Search Bar (Google Maps style)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Search Container
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
                        // Search Suggestions
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
          if (_isLoadingRoute)
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

          // Route Info Bottom Sheet
          if (_routeDetails != null && _dropLocation != null)
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
                      // Drag Handle
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
                        child: Row(
                          children: [
                            // Route Info
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
                            // Clear Button
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _removeDropLocation,
                              tooltip: 'Clear route',
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
            bottom: _routeDetails != null ? 120 : 16,
            child: Column(
              children: [
                // My Location Button
                if (_currentLocation != null)
                  FloatingActionButton(
                    mini: true,
                    heroTag: 'myLocation',
                    onPressed: () => _moveCameraToLocation(_currentLocation!),
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.my_location, color: Colors.blue),
                  ),
                const SizedBox(height: 8),
                // Fit Route Button
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
}
