// import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
// import 'package:location/location.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
//
// void main() {
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return const MaterialApp(
//       home: MapScreen(),
//     );
//   }
// }
//
// class MapScreen extends StatefulWidget {
//   const MapScreen({super.key});
//
//   @override
//   _MapScreenState createState() => _MapScreenState();
// }
//
// class _MapScreenState extends State<MapScreen> {
//   final MapController mapController = MapController();
//   LocationData? currentLocation;
//   List<LatLng> routePoints = [];
//   List<Marker> markers = [];
//   final String orsApiKey =
//       '5b3ce3597851110001cf624860b603e87be6171d4e3515288e69540ae81abac8530d75fa5a10aa56'; // Replace with your OpenRouteService API key
//
//   @override
//   void initState() {
//     super.initState();
//     _getCurrentLocation();
//   }
//
//   Future<void> _getCurrentLocation() async {
//     var location = Location();
//
//     try {
//       var userLocation = await location.getLocation();
//       setState(() {
//         currentLocation = userLocation;
//         markers.add(
//           Marker(
//             width: 80.0,
//             height: 80.0,
//             point: LatLng(userLocation.latitude!, userLocation.longitude!),
//             child:
//             const Icon(Icons.my_location, color: Colors.blue, size: 40.0),
//           ),
//         );
//       });
//     } on Exception {
//       currentLocation = null;
//     }
//
//     location.onLocationChanged.listen((LocationData newLocation) {
//       setState(() {
//         currentLocation = newLocation;
//       });
//     });
//   }
//
//   Future<void> _getRoute(LatLng destination) async {
//     if (currentLocation == null) return;
//
//     final start =
//     LatLng(currentLocation!.latitude!, currentLocation!.longitude!);
//     // final response = await http.get(
//     //   Uri.parse(
//     //       'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$orsApiKey&start=${start.longitude},${start.latitude}&end=${destination.longitude},${destination.latitude}'),
//     // );
//     final url = 'http://router.project-osrm.org/route/v1/driving/'
//         '${start.longitude},${start.latitude};'
//         '${destination.longitude},${destination.latitude}?overview=full&geometries=geojson';
//     final response = await http.get(Uri.parse(url));
//
//     if (response.statusCode == 200) {
//       final data = json.decode(response.body);
//       // final List<dynamic> coords = data['features'][0]['geometry']['coordinates'];
//       final List<dynamic> coords = data['routes'][0]['geometry']['coordinates'];
//       setState(() {
//         routePoints =
//             coords.map((coord) => LatLng(coord[1], coord[0])).toList();
//         markers.add(
//           Marker(
//             width: 80.0,
//             height: 80.0,
//             point: destination,
//             child: const Icon(Icons.location_on, color: Colors.red, size: 40.0),
//           ),
//         );
//       });
//     } else {
//       // Handle errors
//       print('Failed to fetch route');
//     }
//   }
//   void _addDestinationMarker(LatLng point) {
//     setState(() {
//       markers.add(
//         Marker(
//           width: 80.0,
//           height: 80.0,
//           point: point,
//           child: const Icon(Icons.location_on, color: Colors.red, size: 40.0),
//         ),
//       );
//     });
//     _getRoute(point);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('OpenStreetMap with Flutter'),
//       ),
//       body: currentLocation == null
//           ? const Center(child: CircularProgressIndicator())
//           : FlutterMap(
//         mapController: mapController,
//         options: MapOptions(
//           initialCenter: LatLng(
//               currentLocation!.latitude!, currentLocation!.longitude!),
//           initialZoom: 15.0,
//           onTap: (tapPosition, point) => _addDestinationMarker(point),
//         ),
//         children: [
//           TileLayer(
//             urlTemplate:
//             "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
//             subdomains: const ['a', 'b', 'c'],
//           ),
//           MarkerLayer(
//             markers: markers,
//           ),
//           PolylineLayer(
//             polylines: [
//               Polyline(
//                 points: routePoints,
//                 strokeWidth: 4.0,
//                 color: Colors.blue,
//               ),
//             ],
//           ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () {
//           if (currentLocation != null) {
//             mapController.move(
//               LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
//               15.0,
//             );
//           }
//         },
//         child: const Icon(Icons.my_location),
//       ),
//     );
//   }
// }
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

void main2() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController mapController = MapController();
  LocationData? currentLocation;
  List<LatLng> routePoints = [];
  List<Marker> markers = [];
  LatLng? searchedLocation;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    var location = Location();

    try {
      var userLocation = await location.getLocation();
      setState(() {
        currentLocation = userLocation;
        markers.add(
          Marker(
            width: 80.0,
            height: 80.0,
            point: LatLng(userLocation.latitude!, userLocation.longitude!),
            child:
                const Icon(Icons.my_location, color: Colors.blue, size: 40.0),
          ),
        );
      });
    } on Exception {
      currentLocation = null;
    }

    location.onLocationChanged.listen((LocationData newLocation) {
      setState(() {
        currentLocation = newLocation;
      });
    });
  }

  Future<void> _getRoute(LatLng destination) async {
    if (currentLocation == null) return;
    final String orsApiKey =
        '5b3ce3597851110001cf624860b603e87be6171d4e3515288e69540ae81abac8530d75fa5a10aa56'; // Replace with your OpenRouteService API key
    final start =
        LatLng(currentLocation!.latitude!, currentLocation!.longitude!);
    final response = await http.get(
      Uri.parse(
          'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$orsApiKey&start=${start.longitude},${start.latitude}&end=${destination.longitude},${destination.latitude}'),
    );
    // final url = 'http://router.project-osrm.org/route/v1/driving/'
    //     '${start.longitude},${start.latitude};'
    //     '${destination.longitude},${destination.latitude}?overview=full&geometries=geojson';
    //
    // final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> coords =
          data['features'][0]['geometry']['coordinates'];
      // final List<dynamic> coords = data['routes'][0]['geometry']['coordinates'];
      setState(() {
        routePoints =
            coords.map((coord) => LatLng(coord[1], coord[0])).toList();
        markers.add(
          Marker(
            width: 80.0,
            height: 80.0,
            point: destination,
            child: const Icon(Icons.location_on, color: Colors.red, size: 40.0),
          ),
        );
      });
    } else {
      print('Failed to fetch route');
    }
  }

  Future<void> _searchLocation(String query) async {
    // final url =
    //     'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1';
    final url = 'https://nominatim.openstreetmap.org/search?'
        'q=${Uri.encodeComponent(query)}&'
        'format=json&'
        'addressdetails=1&'
        'limit=1&'
        'polygon_geojson=0&'
        'extratags=1&'
        'countrycodes=eg';

    final response = await http.get(Uri.parse(url), headers: {
      'User-Agent':
          'FlutterMapApp/1.0 (your_email@example.com)', // required by Nominatim
    });

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      if (data.isNotEmpty) {
        final lat = double.parse(data[0]['lat']);
        final lon = double.parse(data[0]['lon']);
        setState(() {
          searchedLocation = LatLng(lat, lon);
          markers.add(
            Marker(
              width: 80.0,
              height: 80.0,
              point: searchedLocation!,
              child: const Icon(Icons.place, color: Colors.blue, size: 40.0),
            ),
          );
          mapController.move(searchedLocation!, 15.0);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location not found.")),
        );
      }
    }
  }

  void _addDestinationMarker(LatLng point) {
    setState(() {
      markers.add(
        Marker(
          width: 80.0,
          height: 80.0,
          point: point,
          child: const Icon(Icons.location_on, color: Colors.red, size: 40.0),
        ),
      );
    });
    _getRoute(point);
  }

  void _clearMap() {
    setState(() {
      markers.clear();
      routePoints.clear();
      searchedLocation = null;
      searchController.clear();
      if (currentLocation != null) {
        markers.add(
          Marker(
            width: 80.0,
            height: 80.0,
            point:
                LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
            child:
                const Icon(Icons.my_location, color: Colors.blue, size: 40.0),
          ),
        );
      }
    });
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
        ],
      ),
      body: currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            hintText: 'Search location...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: _searchLocation,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _searchLocation(searchController.text),
                      ),
                    ],
                  ),
                ),
                if (searchedLocation != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.flag),
                      label: const Text("Set as Destination"),
                      onPressed: () => _getRoute(searchedLocation!),
                    ),
                  ),
                Expanded(
                  child: FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: LatLng(currentLocation!.latitude!,
                          currentLocation!.longitude!),
                      initialZoom: 15.0,
                      onTap: (tapPosition, point) =>
                          _addDestinationMarker(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                        subdomains: const ['a', 'b', 'c'],
                      ),
                      MarkerLayer(markers: markers),
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
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (currentLocation != null) {
            mapController.move(
              LatLng(currentLocation!.latitude!, currentLocation!.longitude!),
              15.0,
            );
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
