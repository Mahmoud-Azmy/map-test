import 'dart:math';

import 'package:latlong2/latlong.dart';

// Class to handle UTM conversion
class UTMConverter {
  // Earth's radius and other constants
  static const double _a = 6378137.0; // WGS84 semi-major axis (meters)
  static const double _f = 1 / 298.257223563; // Flattening
  static const double _k0 = 0.9996; // Scale factor
  static final double _e = sqrt(2 * _f - _f * _f); // Eccentricity

  // Convert LatLng to UTM (returns easting, northing, zone, and hemisphere)
  static Map<String, dynamic> latLngToUTM(double lat, double lon) {
    // Determine UTM zone
    int zone = ((lon + 180) / 6).floor() + 1;
    bool isNorthern = lat >= 0;

    // Central meridian for the zone
    double lon0 = (zone * 6 - 183) * pi / 180; // Central meridian in radians

    // Convert to radians
    double phi = lat * pi / 180;
    double lambda = lon * pi / 180;

    // Calculate meridional arc
    double N = _a / sqrt(1 - pow(_e * sin(phi), 2));
    double T = pow(tan(phi), 2).toDouble();
    double C = (_e * _e / (1 - _e * _e)) * pow(cos(phi), 2);
    double A = (lambda - lon0) * cos(phi);

    // Calculate easting (x)
    double M = _a *
        ((1 - _e * _e / 4 - 3 * _e * _e * _e * _e / 64) * phi -
            (3 * _e * _e / 8 + 3 * _e * _e * _e * _e / 32) * sin(2 * phi));
    double easting = _k0 * N * (A + (1 - T + C) * pow(A, 3) / 6) + 500000;

    // Calculate northing (y)
    double northing = _k0 * (M + N * tan(phi) * (A * A / 2));
    if (!isNorthern) northing += 10000000; // Adjust for southern hemisphere

    return {
      'easting': easting,
      'northing': northing,
      'zone': zone,
      'hemisphere': isNorthern ? 'N' : 'S'
    };
  }

  // Convert LatLng to local UTM coordinates relative to a reference point
  static Map<String, double> toLocalUTM(
      double lat, double lon, double refLat, double refLon) {
    var ref = latLngToUTM(refLat, refLon);
    var point = latLngToUTM(lat, lon);

    // Ensure the points are in the same zone
    if (ref['zone'] != point['zone']) {
      throw Exception('Points are in different UTM zones');
    }

    // Calculate local offsets (x, y in meters)
    double x = point['easting'] - ref['easting'];
    double y = point['northing'] - ref['northing'];

    return {'x': x, 'y': y};
  }
}

List<LatLng> interpolatePoints(LatLng start, LatLng end, int numPoints) {
  List<LatLng> interpolatedPoints = [];
  for (int i = 0; i <= numPoints; i++) {
    double fraction = i / numPoints;
    double lat = start.latitude + (end.latitude - start.latitude) * fraction;
    double lon = start.longitude + (end.longitude - start.longitude) * fraction;
    interpolatedPoints.add(LatLng(lat, lon));
  }
  return interpolatedPoints;
}
