import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:io' show File;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:map_test/utm.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'location_web.dart' if (dart.library.io) 'location_stub.dart';

// Service for location-related API calls
class LocationService {
  static const String _nominatimUrl =
      'https://nominatim.openstreetmap.org/search';
  static const String _osrmUrl =
      'http://router.project-osrm.org/route/v1/driving';
  static const String _userAgent = 'FlutterMapApp/1.0';

  Future<LatLng?> searchLocation(String query) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_nominatimUrl?q=$query&format=json&limit=1&addressdetails=1'),
        headers: {'User-Agent': _userAgent},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
            return LatLng(lat, lon);
          }
        }
      }
      return null;
    } catch (e) {
      throw Exception('Error searching location: $e');
    }
  }

  Future<List<LatLng>?> getRoute(LatLng start, LatLng destination) async {
    try {
      final url =
          '$_osrmUrl/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> coords =
            data['routes'][0]['geometry']['coordinates'];
        return coords
            .map((coord) => LatLng(coord[1], coord[0]))
            .where((point) =>
                point.latitude >= -90 &&
                point.latitude <= 90 &&
                point.longitude >= -180 &&
                point.longitude <= 180)
            .toList();
      }
      return null;
    } catch (e) {
      throw Exception('Error fetching route: $e');
    }
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Map and location controllers
  final MapController mapController = MapController();
  final LocationService _locationService = LocationService();
  final Location _location = Location();
  final LocationWebPlugin _locationWeb = LocationWebPlugin();
  final TextEditingController searchController = TextEditingController();

  // State variables
  LocationData? userLocation;
  LatLng? carLocation; // Car's location from WebSocket
  List<LatLng> routePoints = [];
  List<Marker> markers = [];
  bool isLoading = false;
  bool locationPermissionDenied = false;
  bool locationInitialized = false;
  bool isRouteDrawn = false; // Track if route has been drawn
  Timer? _debounce;
  StreamSubscription<LocationData>? _locationSubscription;

  // WebSocket variables
  WebSocketChannel? _webSocketChannel;
  bool isWebSocketConnected = false;
  Completer<LatLng>? _carLocationCompleter; // To wait for car location response

  static const LatLng defaultLocation = LatLng(0, 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSnackBar('Tap the location button to show your current position.');
      _connectWebSocket();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _locationSubscription?.cancel();
    _locationWeb.dispose();
    searchController.dispose();
    _webSocketChannel?.sink.close();
    super.dispose();
  }

  // ====================== Helper Methods ======================
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ====================== WebSocket Methods ======================
  void _connectWebSocket() {
    try {
      const wsUrl = 'ws://127.0.0.1:8765';
      _webSocketChannel = kIsWeb
          ? WebSocketChannel.connect(Uri.parse(wsUrl))
          : IOWebSocketChannel.connect(wsUrl);

      _webSocketChannel!.stream.listen(
        (message) {
          final data = json.decode(message);
          if (data.containsKey('location')) {
            final location = data['location'];
            setState(() {
              carLocation = LatLng(
                location['lat'] as double,
                location['lon'] as double,
              );
              _updateCarMarker();
            });
            if (_carLocationCompleter != null &&
                !_carLocationCompleter!.isCompleted) {
              _carLocationCompleter!.complete(carLocation);
            }
          } else if (data.containsKey('response')) {
            final response = data['response'] ?? 'No response';
            _showSnackBar('Car response: $response');
          }
        },
        onDone: () {
          setState(() => isWebSocketConnected = false);
          _showSnackBar('WebSocket connection closed');
          if (_carLocationCompleter != null &&
              !_carLocationCompleter!.isCompleted) {
            _carLocationCompleter!.completeError('WebSocket connection closed');
          }
        },
        onError: (error) {
          setState(() => isWebSocketConnected = false);
          _showSnackBar('WebSocket error: $error');
          if (_carLocationCompleter != null &&
              !_carLocationCompleter!.isCompleted) {
            _carLocationCompleter!.completeError(error);
          }
        },
      );

      setState(() => isWebSocketConnected = true);
      _showSnackBar('WebSocket connected to car');
    } catch (e) {
      setState(() => isWebSocketConnected = false);
      _showSnackBar('Failed to connect to WebSocket: $e');
      if (_carLocationCompleter != null &&
          !_carLocationCompleter!.isCompleted) {
        _carLocationCompleter!.completeError(e);
      }
    }
  }

  void _sendCommandToCar(String command) {
    if (!isWebSocketConnected || _webSocketChannel == null) {
      _showSnackBar('WebSocket not connected. Please try again.');
      _connectWebSocket();
      return;
    }

    try {
      final commandData = {'command': command};
      _webSocketChannel!.sink.add(jsonEncode(commandData));
      _showSnackBar('Command sent to car: $command');
    } catch (e) {
      _showSnackBar('Failed to send command: $e');
      if (_carLocationCompleter != null &&
          !_carLocationCompleter!.isCompleted) {
        _carLocationCompleter!.completeError(e);
      }
    }
  }

  Future<void> _fetchCarLocation() async {
    if (!isWebSocketConnected || _webSocketChannel == null) {
      _showSnackBar('WebSocket not connected. Please try again.');
      _connectWebSocket();
      return;
    }

    setState(() => isLoading = true);
    _carLocationCompleter = Completer<LatLng>();

    try {
      _sendCommandToCar('GET_LOCATION');
      final location = await _carLocationCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Failed to get car location: Timed out');
        },
      );
      mapController.move(location, 15.0);
    } catch (e) {
      _showSnackBar('Failed to fetch car location: $e');
    } finally {
      setState(() => isLoading = false);
      _carLocationCompleter = null;
    }
  }

  // ====================== Location Methods ======================
  Future<void> _initializeUserLocation() async {
    if (locationInitialized) return;

    setState(() => isLoading = true);

    try {
      if (kIsWeb) {
        await _initializeWebLocation();
      } else {
        await _initializeNativeLocation();
      }
    } catch (e) {
      _showSnackBar('Failed to get location: $e');
      setState(() => locationPermissionDenied = true);
      _showPermissionDialog();
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _initializeWebLocation() async {
    final permissionStatus = await _locationWeb.hasPermission();
    if (permissionStatus != PermissionStatus.granted) {
      final newStatus = await _locationWeb.requestPermission();
      if (newStatus != PermissionStatus.granted) {
        setState(() => locationPermissionDenied = true);
        _showPermissionDialog();
        return;
      }
    }

    final userLocationData = await _locationWeb.getLocation();
    if (userLocationData.latitude != null &&
        userLocationData.longitude != null) {
      setState(() {
        userLocation = userLocationData;
        locationInitialized = true;
        _updateUserMarker();
      });
      mapController.move(
        LatLng(userLocation!.latitude!, userLocation!.longitude!),
        15.0,
      );
    } else {
      _showSnackBar('Invalid location data.');
    }

    _locationSubscription = _locationWeb.onLocationChanged().listen(
      (LocationData newLocation) {
        if (newLocation.latitude != null && newLocation.longitude != null) {
          setState(() {
            userLocation = newLocation;
            _updateUserMarker();
          });
        }
      },
      onError: (e) => _showSnackBar('Location update error: $e'),
    );
  }

  Future<void> _initializeNativeLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        _showSnackBar('Location services are disabled.');
        setState(() => locationPermissionDenied = true);
        _showPermissionDialog();
        return;
      }
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        setState(() => locationPermissionDenied = true);
        _showPermissionDialog();
        return;
      }
    }

    final userLocationData = await _location.getLocation();
    if (userLocationData.latitude != null &&
        userLocationData.longitude != null) {
      setState(() {
        userLocation = userLocationData;
        locationInitialized = true;
        _updateUserMarker();
      });
      mapController.move(
        LatLng(userLocation!.latitude!, userLocation!.longitude!),
        15.0,
      );
    } else {
      _showSnackBar('Invalid location data.');
    }

    _locationSubscription =
        _location.onLocationChanged.listen((LocationData newLocation) {
      if (newLocation.latitude != null && newLocation.longitude != null) {
        setState(() {
          userLocation = newLocation;
          _updateUserMarker();
        });
      }
    });
  }

  Future<void> _retryLocationPermission() async {
    setState(() {
      locationPermissionDenied = false;
      isLoading = true;
    });

    try {
      if (kIsWeb) {
        await _retryWebLocationPermission();
      } else {
        await _retryNativeLocationPermission();
      }
    } catch (e) {
      _showSnackBar('Failed to get location: $e');
      setState(() => locationPermissionDenied = true);
      _showPermissionDialog();
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _retryWebLocationPermission() async {
    final permissionStatus = await _locationWeb.requestPermission();
    if (permissionStatus != PermissionStatus.granted) {
      setState(() => locationPermissionDenied = true);
      _showPermissionDialog();
      return;
    }

    final userLocationData = await _locationWeb.getLocation();
    if (userLocationData.latitude != null &&
        userLocationData.longitude != null) {
      setState(() {
        userLocation = userLocationData;
        locationInitialized = true;
        _updateUserMarker();
      });
      mapController.move(
        LatLng(userLocation!.latitude!, userLocation!.longitude!),
        15.0,
      );
    }

    _locationSubscription?.cancel();
    _locationSubscription = _locationWeb.onLocationChanged().listen(
      (LocationData newLocation) {
        if (newLocation.latitude != null && newLocation.longitude != null) {
          setState(() {
            userLocation = newLocation;
            _updateUserMarker();
          });
        }
      },
      onError: (e) => _showSnackBar('Location update error: $e'),
    );
  }

  Future<void> _retryNativeLocationPermission() async {
    final permissionStatus = await _location.requestPermission();
    if (permissionStatus != PermissionStatus.granted) {
      setState(() => locationPermissionDenied = true);
      _showPermissionDialog();
      return;
    }

    final userLocationData = await _location.getLocation();
    if (userLocationData.latitude != null &&
        userLocationData.longitude != null) {
      setState(() {
        userLocation = userLocationData;
        locationInitialized = true;
        _updateUserMarker();
      });
      mapController.move(
        LatLng(userLocation!.latitude!, userLocation!.longitude!),
        15.0,
      );
    }

    _locationSubscription?.cancel();
    _locationSubscription =
        _location.onLocationChanged.listen((LocationData newLocation) {
      if (newLocation.latitude != null && newLocation.longitude != null) {
        setState(() {
          userLocation = newLocation;
          _updateUserMarker();
        });
      }
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'This app requires location access to show your position on the map. Please enable permissions to continue, or proceed without location access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Without Location'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _retryLocationPermission();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ====================== Marker Methods ======================
  void _updateUserMarker() {
    if (userLocation == null) return;
    markers.removeWhere(
        (m) => m.child is Icon && (m.child as Icon).icon == Icons.my_location);
    markers.add(
      Marker(
        width: 80.0,
        height: 80.0,
        point: LatLng(userLocation!.latitude!, userLocation!.longitude!),
        child: const Icon(Icons.my_location, color: Colors.blue, size: 40.0),
      ),
    );
  }

  void _updateCarMarker() {
    if (carLocation == null) return;
    markers.removeWhere((m) =>
        m.child is Icon && (m.child as Icon).icon == Icons.directions_car);
    markers.add(
      Marker(
        width: 80.0,
        height: 80.0,
        point: carLocation!,
        child:
            const Icon(Icons.directions_car, color: Colors.green, size: 40.0),
      ),
    );
  }

  // ====================== Route Methods ======================
  Future<void> _getRoute(LatLng destination) async {
    if (carLocation == null) {
      _showSnackBar(
          'Car location unavailable. Use the "Get Car Location" button.');
      return;
    }

    setState(() => isLoading = true);
    try {
      final route = await _locationService.getRoute(carLocation!, destination);
      if (route != null) {
        setState(() {
          routePoints = route;
          isRouteDrawn = true; // Set route as drawn
          markers.removeWhere((m) =>
              m.child is Icon && (m.child as Icon).icon == Icons.location_on);
          markers.add(
            Marker(
              width: 80.0,
              height: 80.0,
              point: destination,
              child:
                  const Icon(Icons.location_on, color: Colors.red, size: 40.0),
            ),
          );
        });
      } else {
        _showSnackBar('Failed to fetch route.');
        setState(() => isRouteDrawn = false);
      }
    } catch (e) {
      _showSnackBar('Error fetching route: $e');
      setState(() => isRouteDrawn = false);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _addDestinationMarker(LatLng point) {
    _getRoute(point);
  }

  // ====================== Search Methods ======================
  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    setState(() => isLoading = true);
    try {
      final searchedLocation = await _locationService.searchLocation(query);
      if (searchedLocation != null) {
        setState(() {
          markers.clear();
          routePoints.clear();
          isRouteDrawn = false;
          if (userLocation != null) _updateUserMarker();
          if (carLocation != null) _updateCarMarker();
          _addDestinationMarker(searchedLocation);
        });
        mapController.move(searchedLocation, 15.0);
      } else {
        _showSnackBar('No results found for "$query".');
      }
    } catch (e) {
      _showSnackBar('Error searching location: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchLocation(value.trim());
    });
  }

  // ====================== Map Management Methods ======================
  void _clearMap() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Map'),
        content: const Text(
            'Are you sure you want to clear all markers and routes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                markers.clear();
                routePoints.clear();
                isRouteDrawn = false;
                if (userLocation != null) _updateUserMarker();
                if (carLocation != null) _updateCarMarker();
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  // ====================== CSV Export Methods ======================// ====================== CSV Export Methods ======================
  Future<void> _exportRouteToCSV() async {
    if (routePoints.isEmpty) {
      _showSnackBar('No route data to export.');
      return;
    }

    try {
      // Generate and download CSV in one step
      _generateAndDownloadCsv();
      _showSnackBar('Route data exported successfully.');
    } catch (e) {
      _showSnackBar('Error exporting route: $e');
    }
  }

  void _generateAndDownloadCsv() {
    // Interpolate points for denser route
    List<LatLng> densePoints = [];
    const int pointsBetween = 8;

    for (int i = 0; i < routePoints.length - 1; i++) {
      LatLng start = routePoints[i];
      LatLng end = routePoints[i + 1];
      List<LatLng> interpolated = interpolatePoints(start, end, pointsBetween);
      densePoints.addAll(interpolated.sublist(0, interpolated.length - 1));
    }
    densePoints.add(routePoints.last);

    // Convert to CSV data
    List<Map<String, dynamic>> csvData = [];
    final refPoint = densePoints.first;
    double refLat = refPoint.latitude;
    double refLon = refPoint.longitude;

    for (int i = 0; i < densePoints.length; i++) {
      final currentPoint = densePoints[i];
      final nextPoint =
          (i + 1 < densePoints.length) ? densePoints[i + 1] : null;

      double yaw = 0.0;
      if (nextPoint != null) {
        final deltaLat = nextPoint.latitude - currentPoint.latitude;
        final deltaLng = nextPoint.longitude - currentPoint.longitude;
        yaw = (atan2(deltaLng, deltaLat) * (180 / pi)) % 360;
      }

      var utm = UTMConverter.toLocalUTM(
          currentPoint.latitude, currentPoint.longitude, refLat, refLon);
      double x = utm['x']!;
      double y = utm['y']!;

      double z = 0.325; // Placeholder for elevation
      double mps = 0.5; // Placeholder for speed
      int changeFlag = 0; // Placeholder for change_flag

      csvData.add({
        'x': x.toStringAsFixed(6),
        'y': y.toStringAsFixed(6),
        'z': z.toStringAsFixed(3),
        'yaw': yaw.toStringAsFixed(2),
        'mps': mps.toStringAsFixed(2),
        'change_flag': changeFlag.toString(),
      });
    }

    // Generate CSV content string
    final csvContent =
        'x,y,z,yaw,mps,change_flag\n${csvData.map((row) => '${row['x']},${row['y']},${row['z']},${row['yaw']},${row['mps']},${row['change_flag']}').join('\n')}';

    // Download the CSV file
    _downloadCsvForWeb(csvContent);
  }

  void _downloadCsvForWeb(String csvContent) {
    // Generate filename with timestamp to avoid duplicates
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final filename = 'route_data_$timestamp.csv';

    // Create and trigger download
    final blob = html.Blob([csvContent], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..style.display = 'none'
      ..download = filename;

    html.document.body?.children.add(anchor);
    anchor.click();

    // Clean up
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _saveCsvForNative(String csvContent) async {
    // Define the specific file path where you want to save the CSV
    const filePath = 'D:/book_images/route_data.csv';
    final file = File(filePath);

    try {
      // Check if file exists and delete it
      if (await file.exists()) {
        await file.delete();
      }

      // Create parent directories if they don't exist
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      // Write the new file
      await file.writeAsString(csvContent, flush: true);

      _showSnackBar('Route data saved to $filePath');
    } catch (e) {
      _showSnackBar('Error saving file: $e');
      // Fallback to default location if there's an error
      await _saveCsvToDefaultLocation(csvContent);
    }
  }

  Future<void> _saveCsvToDefaultLocation(String csvContent) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/route_data.csv');

      if (await file.exists()) {
        await file.delete();
      }

      await file.writeAsString(csvContent, flush: true);
      _showSnackBar('Route data saved to default location: ${file.path}');
    } catch (e) {
      _showSnackBar('Error saving to default location: $e');
    }
  }

  List<LatLng> interpolatePoints(LatLng start, LatLng end, int numPoints) {
    List<LatLng> interpolatedPoints = [];
    for (int i = 0; i <= numPoints; i++) {
      double fraction = i / numPoints;
      double lat = start.latitude + (end.latitude - start.latitude) * fraction;
      double lon =
          start.longitude + (end.longitude - start.longitude) * fraction;
      interpolatedPoints.add(LatLng(lat, lon));
    }
    return interpolatedPoints;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenStreetMap with Flutter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearMap,
            tooltip: 'Clear Map',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportRouteToCSV,
            tooltip: 'Export Route to CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Search Location',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () =>
                      _searchLocation(searchController.text.trim()),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: userLocation != null
                        ? LatLng(
                            userLocation!.latitude!, userLocation!.longitude!)
                        : defaultLocation,
                    initialZoom: userLocation != null ? 15.0 : 2.0,
                    onTap: (tapPosition, point) => _addDestinationMarker(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      tileProvider: CancellableNetworkTileProvider(),
                    ),
                    MarkerLayer(markers: markers),
                    if (routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePoints,
                            strokeWidth: 4.0,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                  ],
                ),
                if (isLoading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () {
              if (!locationInitialized || locationPermissionDenied) {
                _initializeUserLocation();
              } else if (userLocation != null) {
                mapController.move(
                  LatLng(userLocation!.latitude!, userLocation!.longitude!),
                  15.0,
                );
              } else {
                _showSnackBar(
                    'Location unavailable. Please enable location permissions.');
              }
            },
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: _fetchCarLocation,
            backgroundColor: isWebSocketConnected ? Colors.green : Colors.grey,
            tooltip: 'Get Car Location',
            child: const Icon(Icons.directions_car),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: isRouteDrawn && isWebSocketConnected
                ? () {
                    _exportRouteToCSV();
                    _sendCommandToCar('START');
                  }
                : null,
            backgroundColor: isRouteDrawn && isWebSocketConnected
                ? Colors.green
                : Colors.grey,
            tooltip: isRouteDrawn
                ? 'Send Start Command to Car'
                : 'Draw a route first',
            child: const Icon(Icons.play_arrow),
          ),
        ],
      ),
    );
  }
}
