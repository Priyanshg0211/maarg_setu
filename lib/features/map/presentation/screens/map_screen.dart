import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

import '../../../../core/constants/map_constants.dart';
import '../../services/location_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final LocationService _locationService = LocationService();

  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;

  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _initLocationUpdates();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
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
  }

  void _updateMarker(LocationData locationData) {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) return;

    _markers
      ..clear()
      ..add(
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
        title: const Text('Live Location with Radar'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initLocationUpdates,
            tooltip: 'Refresh Location',
          ),
        ],
      ),
      body: GoogleMap(
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
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
        compassEnabled: true,
        onMapCreated: (controller) {
          _controller.complete(controller);
        },
      ),
      floatingActionButton: _currentLocation != null
          ? FloatingActionButton(
              onPressed: () => _moveCameraToLocation(_currentLocation!),
              backgroundColor: Colors.blue,
              child: const Icon(Icons.my_location),
            )
          : null,
    );
  }
}
