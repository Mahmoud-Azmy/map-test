import 'dart:async';
import 'dart:js' as js;

import 'package:location/location.dart';

class LocationWebPlugin {
  StreamController<LocationData>? _locationController;
  int? _watchId;

  Future<LocationData> getLocation() async {
    try {
      final position = await _getCurrentPosition();
      return _toLocationData(position);
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  Future<PermissionStatus> hasPermission() async {
    try {
      final permissions = js.context['navigator']['permissions'];
      if (permissions == null) {
        return PermissionStatus.denied;
      }

      final result =
          await js.context['navigator']['permissions'].callMethod('query', [
        js.JsObject.jsify({'name': 'geolocation'})
      ]);
      final state = result['state'] as String;

      switch (state) {
        case 'granted':
          return PermissionStatus.granted;
        case 'prompt':
          return PermissionStatus.denied;
        case 'denied':
          return PermissionStatus.deniedForever;
        default:
          return PermissionStatus.denied;
      }
    } catch (e) {
      print('Error checking geolocation permissions: $e');
      return PermissionStatus.denied;
    }
  }

  Future<PermissionStatus> requestPermission() async {
    try {
      // Trigger a location request to prompt the user
      await _getCurrentPosition();
      return PermissionStatus.granted;
    } catch (e) {
      return await hasPermission();
    }
  }

  Stream<LocationData> onLocationChanged() {
    _locationController?.close();
    _locationController = StreamController<LocationData>.broadcast();

    final geolocation = js.context['navigator']['geolocation'];
    if (geolocation == null) {
      _locationController?.addError(Exception('Geolocation is not supported.'));
      return _locationController!.stream;
    }

    _watchId = geolocation.callMethod('watchPosition', [
      (position) {
        final locationData = _toLocationData(position);
        _locationController?.add(locationData);
      },
      (error) {
        _locationController
            ?.addError(Exception('Geolocation error: ${error['message']}'));
      },
    ]);

    _locationController?.onCancel = () {
      if (_watchId != null) {
        geolocation.callMethod('clearWatch', [_watchId]);
        _watchId = null;
      }
    };

    return _locationController!.stream;
  }

  Future<js.JsObject> _getCurrentPosition() async {
    final completer = Completer<js.JsObject>();
    final geolocation = js.context['navigator']['geolocation'];

    if (geolocation == null) {
      completer.completeError(Exception('Geolocation is not supported.'));
    } else {
      geolocation.callMethod('getCurrentPosition', [
        (position) {
          completer.complete(position);
        },
        (error) {
          completer.completeError(
              Exception('Geolocation error: ${error['message']}'));
        },
      ]);
    }

    return completer.future;
  }

  LocationData _toLocationData(js.JsObject position) {
    final coords = position['coords'];
    return LocationData.fromMap({
      'latitude': coords['latitude'] as double,
      'longitude': coords['longitude'] as double,
      'accuracy': coords['accuracy'] as double,
      'altitude': coords['altitude'] as double?,
      'heading': coords['heading'] as double?,
      'speed': coords['speed'] as double?,
      'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
    });
  }

  void dispose() {
    _locationController?.close();
    final geolocation = js.context['navigator']['geolocation'];
    if (_watchId != null && geolocation != null) {
      geolocation.callMethod('clearWatch', [_watchId]);
      _watchId = null;
    }
  }
}
