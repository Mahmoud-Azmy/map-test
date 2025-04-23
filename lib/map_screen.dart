import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:io' show Directory, File;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:share_plus/share_plus.dart';
import 'location_web.dart' if (dart.library.io) 'location_stub.dart';

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
  final MapController mapController = MapController();
  final LocationService _locationService = LocationService();
  final Location _location = Location();
  final LocationWebPlugin _locationWeb = LocationWebPlugin();
  final TextEditingController searchController = TextEditingController();
  LocationData? currentLocation;
  List<LatLng> routePoints = [];
  List<Marker> markers = [];
  bool isLoading = false;
  bool locationPermissionDenied = false;
  bool locationInitialized = false;
  Timer? _debounce;
  StreamSubscription<LocationData>? _locationSubscription;

  static const LatLng defaultLocation =
      LatLng(0, 0); // Default fallback location

  @override
  void initState() {
    super.initState();
    // Show a hint to the user about location features
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSnackBar('Tap the location button to show your current position.');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _locationSubscription?.cancel();
    _locationWeb.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    if (locationInitialized) return;

    setState(() {
      isLoading = true;
    });

    try {
      if (kIsWeb) {
        // Web-specific location handling
        final permissionStatus = await _locationWeb.hasPermission();
        if (permissionStatus != PermissionStatus.granted) {
          final newStatus = await _locationWeb.requestPermission();
          if (newStatus != PermissionStatus.granted) {
            setState(() {
              locationPermissionDenied = true;
            });
            _showPermissionDialog();
            return;
          }
        }

        final userLocation = await _locationWeb.getLocation();
        if (userLocation.latitude != null && userLocation.longitude != null) {
          setState(() {
            currentLocation = userLocation;
            _addCurrentLocationMarker();
            locationInitialized = true;
          });
          mapController.move(
            LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
            15.0,
          );
        } else {
          _showSnackBar('Invalid location data.');
        }

        _locationSubscription = _locationWeb.onLocationChanged().listen(
          (LocationData newLocation) {
            if (newLocation.latitude != null && newLocation.longitude != null) {
              setState(() {
                currentLocation = newLocation;
                _updateCurrentLocationMarker();
              });
            }
          },
          onError: (e) {
            _showSnackBar('Location update error: $e');
          },
        );
      } else {
        // Native platform handling
        bool serviceEnabled = await _location.serviceEnabled();
        if (!serviceEnabled) {
          serviceEnabled = await _location.requestService();
          if (!serviceEnabled) {
            _showSnackBar('Location services are disabled.');
            setState(() {
              locationPermissionDenied = true;
            });
            _showPermissionDialog();
            return;
          }
        }

        PermissionStatus permissionGranted = await _location.hasPermission();
        if (permissionGranted == PermissionStatus.denied) {
          permissionGranted = await _location.requestPermission();
          if (permissionGranted != PermissionStatus.granted) {
            setState(() {
              locationPermissionDenied = true;
            });
            _showPermissionDialog();
            return;
          }
        }

        final userLocation = await _location.getLocation();
        if (userLocation.latitude != null && userLocation.longitude != null) {
          setState(() {
            currentLocation = userLocation;
            _addCurrentLocationMarker();
            locationInitialized = true;
          });
          mapController.move(
            LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
            15.0,
          );
        } else {
          _showSnackBar('Invalid location data.');
        }

        _locationSubscription =
            _location.onLocationChanged.listen((LocationData newLocation) {
          if (newLocation.latitude != null && newLocation.longitude != null) {
            setState(() {
              currentLocation = newLocation;
              _updateCurrentLocationMarker();
            });
          }
        });
      }
    } catch (e) {
      _showSnackBar('Failed to get location: $e');
      setState(() {
        locationPermissionDenied = true;
      });
      _showPermissionDialog();
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _retryLocationPermission() async {
    setState(() {
      locationPermissionDenied = false;
      isLoading = true;
    });

    try {
      if (kIsWeb) {
        final permissionStatus = await _locationWeb.requestPermission();
        if (permissionStatus == PermissionStatus.granted) {
          final userLocation = await _locationWeb.getLocation();
          if (userLocation.latitude != null && userLocation.longitude != null) {
            setState(() {
              currentLocation = userLocation;
              _addCurrentLocationMarker();
              locationInitialized = true;
            });
            mapController.move(
              LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
              15.0,
            );
          }
          _locationSubscription?.cancel();
          _locationSubscription = _locationWeb.onLocationChanged().listen(
            (LocationData newLocation) {
              if (newLocation.latitude != null &&
                  newLocation.longitude != null) {
                setState(() {
                  currentLocation = newLocation;
                  _updateCurrentLocationMarker();
                });
              }
            },
            onError: (e) {
              _showSnackBar('Location update error: $e');
            },
          );
        } else {
          setState(() {
            locationPermissionDenied = true;
          });
          _showPermissionDialog();
        }
      } else {
        final permissionStatus = await _location.requestPermission();
        if (permissionStatus == PermissionStatus.granted) {
          final userLocation = await _location.getLocation();
          if (userLocation.latitude != null && userLocation.longitude != null) {
            setState(() {
              currentLocation = userLocation;
              _addCurrentLocationMarker();
              locationInitialized = true;
            });
            mapController.move(
              LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
              15.0,
            );
          }
          _locationSubscription?.cancel();
          _locationSubscription =
              _location.onLocationChanged.listen((LocationData newLocation) {
            if (newLocation.latitude != null && newLocation.longitude != null) {
              setState(() {
                currentLocation = newLocation;
                _updateCurrentLocationMarker();
              });
            }
          });
        } else {
          setState(() {
            locationPermissionDenied = true;
          });
          _showPermissionDialog();
        }
      }
    } catch (e) {
      _showSnackBar('Failed to get location: $e');
      setState(() {
        locationPermissionDenied = true;
      });
      _showPermissionDialog();
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'This app requires location access to show your current position on the map. Please enable location permissions to continue, or proceed without location access.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Proceed without location
            },
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

  void _addCurrentLocationMarker() {
    markers.removeWhere(
        (m) => m.child is Icon && (m.child as Icon).icon == Icons.my_location);
    markers.add(
      Marker(
        width: 80.0,
        height: 80.0,
        point: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
        child: const Icon(Icons.my_location, color: Colors.blue, size: 40.0),
      ),
    );
  }

  void _updateCurrentLocationMarker() {
    markers.removeWhere(
        (m) => m.child is Icon && (m.child as Icon).icon == Icons.my_location);
    markers.add(
      Marker(
        width: 80.0,
        height: 80.0,
        point: LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
        child: const Icon(Icons.my_location, color: Colors.blue, size: 40.0),
      ),
    );
  }

  Future<void> _getRoute(LatLng destination) async {
    if (currentLocation == null ||
        currentLocation!.latitude == null ||
        currentLocation!.longitude == null) {
      _showSnackBar(
          'Current location unavailable. Please enable location permissions or search for a starting location.');
      return;
    }

    setState(() => isLoading = true);
    final start =
        LatLng(currentLocation!.latitude!, currentLocation!.longitude!);
    try {
      final route = await _locationService.getRoute(start, destination);
      if (route != null) {
        setState(() {
          routePoints = route;
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
      }
    } catch (e) {
      _showSnackBar('Error fetching route: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _addDestinationMarker(LatLng point) {
    _getRoute(point);
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    setState(() => isLoading = true);
    try {
      final searchedLocation = await _locationService.searchLocation(query);
      if (searchedLocation != null) {
        setState(() {
          markers.clear();
          routePoints.clear();
          if (currentLocation != null) {
            _addCurrentLocationMarker();
          }
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
                if (currentLocation != null) {
                  _addCurrentLocationMarker();
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportRouteToCSV() async {
    if (routePoints.isEmpty) {
      _showSnackBar('No route data to export.');
      return;
    }

    List<Map<String, dynamic>> csvData = [];
    for (int i = 0; i < routePoints.length; i++) {
      final currentPoint = routePoints[i];
      final nextPoint =
          (i + 1 < routePoints.length) ? routePoints[i + 1] : null;

      double yaw = 0.0;
      if (nextPoint != null) {
        final deltaLat = nextPoint.latitude - currentPoint.latitude;
        final deltaLng = nextPoint.longitude - currentPoint.longitude;
        yaw = (atan2(deltaLng, deltaLat) * (180 / pi)) % 360;
      }

      csvData.add({
        'Latitude': currentPoint.latitude.toStringAsFixed(6),
        'Longitude': currentPoint.longitude.toStringAsFixed(6),
        'Yaw': yaw.toStringAsFixed(2),
      });
    }

    final csvContent =
        'Latitude,Longitude,Yaw\n${csvData.map((row) => '${row['Latitude']},${row['Longitude']},${row['Yaw']}').join('\n')}';

    try {
      if (kIsWeb) {
        final blob = html.Blob([csvContent], 'text/csv');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..style.display = 'none'
          ..download = 'route_data.csv';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        final file = await File('${Directory.systemTemp.path}/route_data.csv')
            .writeAsString(csvContent);
        await Share.shareXFiles([XFile(file.path)], text: 'Exported route data');
      }
      _showSnackBar('Route data exported successfully.');
    } catch (e) {
      _showSnackBar('Error exporting route: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                    initialCenter: currentLocation != null
                        ? LatLng(currentLocation!.latitude!,
                            currentLocation!.longitude!)
                        : defaultLocation,
                    initialZoom: currentLocation != null ? 15.0 : 2.0,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (!locationInitialized || locationPermissionDenied) {
            _initializeLocation();
          } else if (currentLocation != null) {
            mapController.move(
              LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
              15.0,
            );
          } else {
            _showSnackBar(
                'Location unavailable. Please enable location permissions.');
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
