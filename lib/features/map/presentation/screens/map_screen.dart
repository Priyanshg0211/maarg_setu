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
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchSuggestions = [];
  String? _destinationAddress;

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

    if (moveCamera) {
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
          BitmapDescriptor.hueAzure,
        ),
      ),
    );
  }

  void _addDropLocationMarker(LatLng position) {
    // Optional: Keep marker minimal or remove it entirely
    // For now, keeping a subtle marker
    _markers.removeWhere((marker) => marker.markerId.value == 'dropLocation');
    
    _markers.add(
      Marker(
        markerId: const MarkerId('dropLocation'),
        position: position,
        infoWindow: const InfoWindow(
          title: 'Destination',
          snippet: 'Route destination',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
      ),
    );
  }

  void _removeDropLocation() {
    setState(() {
      _dropLocation = null;
      _destinationAddress = null;
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
      final routePoints = await _directionsService.getRoutePoints(
        origin: origin,
        destination: _dropLocation!,
      );

      setState(() {
        _polylines.clear();
        if (routePoints != null && routePoints.isNotEmpty) {
          // Draw the detailed route path like Google Maps
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: routePoints,
              color: const Color(0xFF4285F4), // Google Maps blue color
              width: 6, // Slightly thicker for better visibility
              patterns: [],
              geodesic: true, // Follows the curvature of the Earth
              jointType: JointType.round, // Smooth rounded joints
              endCap: Cap.roundCap, // Rounded line ends
              startCap: Cap.roundCap,
            ),
          );
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
      _destinationAddress = null;
      _destinationController.clear();
      _addDropLocationMarker(position);
    });
    _fetchRoute();
  }

  Future<void> _searchDestination(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final suggestions = await _geocodingService.searchPlaces(query);
      setState(() {
        _searchSuggestions = suggestions;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
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
          _destinationAddress = address;
          _addDropLocationMarker(location);
        });
        _fetchRoute();
        
        // Move camera to show both locations
        if (_currentLocation != null) {
          final controller = await _controller.future;
          controller.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(
                  _currentLocation!.latitude! < location.latitude
                      ? _currentLocation!.latitude!
                      : location.latitude,
                  _currentLocation!.longitude! < location.longitude
                      ? _currentLocation!.longitude!
                      : location.longitude,
                ),
                northeast: LatLng(
                  _currentLocation!.latitude! > location.latitude
                      ? _currentLocation!.latitude!
                      : location.latitude,
                  _currentLocation!.longitude! > location.longitude
                      ? _currentLocation!.longitude!
                      : location.longitude,
                ),
              ),
              padding: const EdgeInsets.all(100),
            ),
          );
        }
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
          _destinationAddress = description;
          _addDropLocationMarker(location);
        });
        _fetchRoute();
        
        // Move camera to show both locations
        if (_currentLocation != null) {
          final controller = await _controller.future;
          controller.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(
                  _currentLocation!.latitude! < location.latitude
                      ? _currentLocation!.latitude!
                      : location.latitude,
                  _currentLocation!.longitude! < location.longitude
                      ? _currentLocation!.longitude!
                      : location.longitude,
                ),
                northeast: LatLng(
                  _currentLocation!.latitude! > location.latitude
                      ? _currentLocation!.latitude!
                      : location.latitude,
                  _currentLocation!.longitude! > location.longitude
                      ? _currentLocation!.longitude!
                      : location.longitude,
                ),
              ),
              padding: const EdgeInsets.all(100),
            ),
          );
        }
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
          fillColor: Colors.blue.withOpacity(0.2),
          strokeColor: Colors.blue,
          strokeWidth: 2,
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location with Route'),
        backgroundColor: Colors.blue,
        actions: [
          if (_dropLocation != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _removeDropLocation,
              tooltip: 'Clear Drop Location',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initLocationUpdates,
            tooltip: 'Refresh Location',
          ),
        ],
      ),
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
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            compassEnabled: true,
            onMapCreated: (controller) {
              _controller.complete(controller);
            },
            onTap: _onMapTap,
          ),
          // Destination Search Bar
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _destinationController,
                    focusNode: _destinationFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Enter destination address',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _dropLocation != null || _destinationController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _destinationController.clear();
                                _removeDropLocation();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    onChanged: (value) {
                      setState(() {});
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
                  // Search Suggestions
                  if (_searchSuggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchSuggestions.length,
                        itemBuilder: (context, index) {
                          final suggestion = _searchSuggestions[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on),
                            title: Text(suggestion['description'] as String),
                            onTap: () {
                              _setDestinationFromPlaceId(
                                suggestion['place_id'] as String,
                                suggestion['description'] as String,
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_isLoadingRoute)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (_dropLocation == null && _destinationController.text.isEmpty)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.blue.withOpacity(0.9),
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'Enter destination address or tap on the map',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _currentLocation != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_dropLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FloatingActionButton(
                      onPressed: () {
                        final controller = _controller.future;
                        controller.then((ctrl) {
                          ctrl.animateCamera(
                            CameraUpdate.newLatLngBounds(
                              LatLngBounds(
                                southwest: LatLng(
                                  _currentLocation!.latitude! < _dropLocation!.latitude
                                      ? _currentLocation!.latitude!
                                      : _dropLocation!.latitude,
                                  _currentLocation!.longitude! < _dropLocation!.longitude
                                      ? _currentLocation!.longitude!
                                      : _dropLocation!.longitude,
                                ),
                                northeast: LatLng(
                                  _currentLocation!.latitude! > _dropLocation!.latitude
                                      ? _currentLocation!.latitude!
                                      : _dropLocation!.latitude,
                                  _currentLocation!.longitude! > _dropLocation!.longitude
                                      ? _currentLocation!.longitude!
                                      : _dropLocation!.longitude,
                                ),
                              ),
                              padding: const EdgeInsets.all(100),
                            ),
                          );
                        });
                      },
                      backgroundColor: Colors.green,
                      child: const Icon(Icons.fit_screen),
                      tooltip: 'Fit Route',
                    ),
                  ),
                FloatingActionButton(
                  onPressed: () => _moveCameraToLocation(_currentLocation!),
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.my_location),
                  tooltip: 'My Location',
                ),
              ],
            )
          : null,
    );
  }
}
