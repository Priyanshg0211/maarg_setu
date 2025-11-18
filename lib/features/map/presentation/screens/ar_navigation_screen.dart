import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;

import '../../services/ar_navigation_service.dart';
import '../../services/location_service.dart';
import '../../services/directions_service.dart';

class ARNavigationScreen extends StatefulWidget {
  final LatLng? destination;
  final RouteDetails? routeDetails;
  final int currentStepIndex;
  final LocationData? currentLocation;

  const ARNavigationScreen({
    super.key,
    this.destination,
    this.routeDetails,
    this.currentStepIndex = 0,
    this.currentLocation,
  });

  @override
  State<ARNavigationScreen> createState() => _ARNavigationScreenState();
}

class _ARNavigationScreenState extends State<ARNavigationScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _hasPermission = false;
  
  final ARNavigationService _arService = ARNavigationService();
  final LocationService _locationService = LocationService();
  
  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;
  double _deviceBearing = 0.0;
  Timer? _updateTimer;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentLocation = widget.currentLocation;
    _initializeCamera();
    _arService.startListening();
    _arService.bearingNotifier.addListener(_onBearingChanged);
    _startLocationUpdates();
    _startUpdateTimer();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final controller = _cameraController;
    
    if (controller == null || !controller.value.isInitialized) {
      if (state == AppLifecycleState.resumed && !_isCameraInitialized) {
        _checkAndInitializeCamera();
      }
      return;
    }
    
    if (state == AppLifecycleState.inactive) {
      // Camera is going to be paused
      controller.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      // Re-check camera permission when app comes back to foreground
      if (!_isCameraInitialized) {
        _checkAndInitializeCamera();
      } else {
        // Camera is already initialized, just ensure it's working
        setState(() {});
      }
    } else if (state == AppLifecycleState.paused) {
      // Don't dispose on pause, just stop the stream
      controller.stopImageStream();
    }
  }
  
  void _onBearingChanged() {
    setState(() {
      _deviceBearing = _arService.deviceBearing;
    });
  }
  
  Future<void> _checkAndInitializeCamera() async {
    // Dispose existing camera first
    await _disposeCamera();
    // Small delay to ensure cleanup
    await Future.delayed(const Duration(milliseconds: 300));
    // Re-initialize
    await _initializeCamera();
  }
  
  Future<void> _initializeCamera() async {
    try {
      // Check current permission status first
      final currentStatus = await permission_handler.Permission.camera.status;
      
      // If permission is permanently denied, show settings option
      if (currentStatus.isPermanentlyDenied) {
        setState(() {
          _hasPermission = false;
        });
        return;
      }
      
      // Request camera permission if not granted
      permission_handler.PermissionStatus status;
      if (currentStatus.isDenied) {
        status = await permission_handler.Permission.camera.request();
      } else {
        status = currentStatus;
      }
      
      if (status != permission_handler.PermissionStatus.granted) {
        setState(() {
          _hasPermission = false;
        });
        return;
      }
      
      _hasPermission = true;
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No cameras available on this device.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Use back camera, prefer back camera for AR
      CameraDescription? backCamera;
      try {
        backCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
      } catch (e) {
        // If no back camera found, use first available
        backCamera = _cameras!.first;
        debugPrint('Back camera not found, using: ${backCamera.name}');
      }
      
      // Dispose existing controller if any
      await _cameraController?.dispose();
      _cameraController = null;
      
      debugPrint('Initializing camera: ${backCamera.name}');
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium, // Changed from high to medium for better compatibility
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      // Verify camera is actually initialized
      if (!_cameraController!.value.isInitialized) {
        throw Exception('Camera failed to initialize');
      }
      
      // Small delay to ensure camera is ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        debugPrint('Camera initialized successfully');
      }
    } catch (e, stackTrace) {
      debugPrint('Error initializing camera: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _isCameraInitialized = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      // Dispose controller on error
      await _cameraController?.dispose();
      _cameraController = null;
    }
  }
  
  Future<void> _startLocationUpdates() async {
    try {
      _locationSubscription?.cancel();
      _locationSubscription = _locationService.locationStream().listen(
        (location) {
          setState(() {
            _currentLocation = location;
          });
        },
      );
    } catch (e) {
      debugPrint('Error starting location updates: $e');
    }
  }
  
  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    _locationSubscription?.cancel();
    _cameraController?.dispose();
    _arService.stopListening();
    _arService.bearingNotifier.removeListener(_onBearingChanged);
    super.dispose();
  }
  
  Future<void> _disposeCamera() async {
    await _cameraController?.dispose();
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
    }
  }
  
  LatLng? get _currentLatLng {
    if (_currentLocation?.latitude == null || _currentLocation?.longitude == null) {
      return null;
    }
    return LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
  }
  
  NavigationStep? get _currentStep {
    if (widget.routeDetails == null || widget.routeDetails!.steps.isEmpty) {
      return null;
    }
    final index = math.min(widget.currentStepIndex, widget.routeDetails!.steps.length - 1);
    return widget.routeDetails!.steps[index];
  }
  
  double? _getBearingToDestination() {
    if (_currentLatLng == null || widget.destination == null) {
      return null;
    }
    return _arService.calculateBearing(_currentLatLng!, widget.destination!);
  }
  
  double? _getDistanceToDestination() {
    if (_currentLatLng == null || widget.destination == null) {
      return null;
    }
    return _arService.calculateDistance(_currentLatLng!, widget.destination!);
  }
  
  double? _getBearingToNextStep() {
    if (_currentLatLng == null || _currentStep == null) {
      return null;
    }
    return _arService.calculateBearing(_currentLatLng!, _currentStep!.location);
  }
  
  double? _getDistanceToNextStep() {
    if (_currentLatLng == null || _currentStep == null) {
      return null;
    }
    return _arService.calculateDistance(_currentLatLng!, _currentStep!.location);
  }
  
  String _formatDistance(double distance) {
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            )
          else if (!_hasPermission)
            _buildPermissionDeniedView()
          else
            _buildLoadingView(),
          
          // AR Overlays
          if (_isCameraInitialized && _currentLatLng != null)
            _buildAROverlays(),
          
          // Top Bar
          SafeArea(
            child: _buildTopBar(),
          ),
          
          // Bottom Navigation Info
          if (_isCameraInitialized && _currentLatLng != null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _buildBottomInfo(),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildPermissionDeniedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, size: 64, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            'Camera Permission Required',
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please enable camera access to use AR navigation',
            style: GoogleFonts.montserrat(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              try {
                final opened = await permission_handler.openAppSettings();
                if (!opened) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Unable to open settings. Please open manually.',
                          style: GoogleFonts.montserrat(),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  // Wait a bit and then re-check permissions when user returns
                  Future.delayed(const Duration(seconds: 1), () {
                    if (mounted) {
                      _checkAndInitializeCamera();
                    }
                  });
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error opening settings: $e',
                        style: GoogleFonts.montserrat(),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: Text(
              'Open Settings',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLoadingView() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
  
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.navigation, color: Colors.blue[300], size: 20),
                const SizedBox(width: 8),
                Text(
                  'AR Navigation',
                  style: GoogleFonts.montserrat(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAROverlays() {
    final screenSize = MediaQuery.of(context).size;
    final bearingToDest = _getBearingToDestination();
    final distanceToDest = _getDistanceToDestination();
    final bearingToStep = _getBearingToNextStep();
    final distanceToStep = _getDistanceToNextStep();
    
    return CustomPaint(
      painter: AROverlayPainter(
        currentLocation: _currentLatLng!,
        destination: widget.destination,
        currentStep: _currentStep,
        deviceBearing: _deviceBearing,
        bearingToDestination: bearingToDest,
        bearingToStep: bearingToStep,
        distanceToDestination: distanceToDest,
        distanceToStep: distanceToStep,
      ),
      size: screenSize,
    );
  }
  
  Widget _buildBottomInfo() {
    final distanceToDest = _getDistanceToDestination();
    final distanceToStep = _getDistanceToNextStep();
    final currentStep = _currentStep;
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (distanceToDest != null)
            Row(
              children: [
                Icon(Icons.place, color: Colors.red[300], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Destination: ${_formatDistance(distanceToDest)}',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          if (currentStep != null && distanceToStep != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.navigation, color: Colors.blue[300], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next: ${_formatDistance(distanceToStep)}',
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentStep.instruction,
                        style: GoogleFonts.montserrat(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class AROverlayPainter extends CustomPainter {
  final LatLng currentLocation;
  final LatLng? destination;
  final NavigationStep? currentStep;
  final double deviceBearing;
  final double? bearingToDestination;
  final double? bearingToStep;
  final double? distanceToDestination;
  final double? distanceToStep;
  
  AROverlayPainter({
    required this.currentLocation,
    this.destination,
    this.currentStep,
    required this.deviceBearing,
    this.bearingToDestination,
    this.bearingToStep,
    this.distanceToDestination,
    this.distanceToStep,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    
    // Draw center crosshair
    _drawCrosshair(canvas, centerX, centerY);
    
    // Draw direction arrow to destination
    if (destination != null && bearingToDestination != null) {
      final angleDiff = _calculateAngleDifference(deviceBearing, bearingToDestination!);
      if (angleDiff.abs() < 45) { // Only show if within 45 degrees
        _drawDirectionArrow(
          canvas,
          centerX,
          centerY - 100,
          angleDiff,
          Colors.red,
          'Destination',
          distanceToDestination,
        );
      }
    }
    
    // Draw direction arrow to next step
    if (currentStep != null && bearingToStep != null) {
      final angleDiff = _calculateAngleDifference(deviceBearing, bearingToStep!);
      if (angleDiff.abs() < 45) { // Only show if within 45 degrees
        _drawDirectionArrow(
          canvas,
          centerX,
          centerY - 50,
          angleDiff,
          Colors.blue,
          'Next Step',
          distanceToStep,
        );
      }
    }
    
    // Draw compass
    _drawCompass(canvas, size.width - 100, 100);
  }
  
  void _drawCrosshair(Canvas canvas, double x, double y) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 2;
    
    // Horizontal line
    canvas.drawLine(
      Offset(x - 20, y),
      Offset(x + 20, y),
      paint,
    );
    
    // Vertical line
    canvas.drawLine(
      Offset(x, y - 20),
      Offset(x, y + 20),
      paint,
    );
    
    // Center circle
    canvas.drawCircle(
      Offset(x, y),
      5,
      Paint()..color = Colors.white.withOpacity(0.8),
    );
  }
  
  void _drawDirectionArrow(
    Canvas canvas,
    double x,
    double y,
    double angle,
    Color color,
    String label,
    double? distance,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path();
    final arrowSize = 30.0;
    
    // Rotate arrow based on angle
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle * math.pi / 180);
    
    // Draw arrow pointing up
    path.moveTo(0, -arrowSize);
    path.lineTo(-arrowSize / 2, 0);
    path.lineTo(0, arrowSize / 3);
    path.lineTo(arrowSize / 2, 0);
    path.close();
    
    canvas.drawPath(path, paint);
    
    // Draw outline
    final outlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, outlinePaint);
    
    canvas.restore();
    
    // Draw label and distance
    if (distance != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${label}\n${_formatDistance(distance)}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 4,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y + 40),
      );
    }
  }
  
  void _drawCompass(Canvas canvas, double x, double y) {
    final radius = 40.0;
    final center = Offset(x, y);
    
    // Draw compass circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withOpacity(0.6)
        ..style = PaintingStyle.fill,
    );
    
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    
    // Draw north indicator
    final northPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    final northPath = Path();
    northPath.moveTo(x, y - radius);
    northPath.lineTo(x - 5, y - radius + 10);
    northPath.lineTo(x + 5, y - radius + 10);
    northPath.close();
    canvas.drawPath(northPath, northPaint);
    
    // Draw bearing indicator
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-deviceBearing * math.pi / 180);
    
    final bearingPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    
    final bearingPath = Path();
    bearingPath.moveTo(0, -radius + 5);
    bearingPath.lineTo(-3, 0);
    bearingPath.lineTo(0, 5);
    bearingPath.lineTo(3, 0);
    bearingPath.close();
    canvas.drawPath(bearingPath, bearingPaint);
    
    canvas.restore();
  }
  
  double _calculateAngleDifference(double deviceBearing, double targetBearing) {
    double diff = targetBearing - deviceBearing;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }
  
  String _formatDistance(double distance) {
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }
  
  @override
  bool shouldRepaint(AROverlayPainter oldDelegate) {
    return oldDelegate.deviceBearing != deviceBearing ||
        oldDelegate.bearingToDestination != bearingToDestination ||
        oldDelegate.bearingToStep != bearingToStep ||
        oldDelegate.distanceToDestination != distanceToDestination ||
        oldDelegate.distanceToStep != distanceToStep;
  }
}

