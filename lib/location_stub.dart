import 'package:location/location.dart';

class LocationWebPlugin {
  Future<LocationData> getLocation() async {
    throw UnimplementedError('LocationWebPlugin is only for web platforms.');
  }

  Future<PermissionStatus> hasPermission() async {
    throw UnimplementedError('LocationWebPlugin is only for web platforms.');
  }

  Future<PermissionStatus> requestPermission() async {
    throw UnimplementedError('LocationWebPlugin is only for web platforms.');
  }

  Stream<LocationData> onLocationChanged() {
    throw UnimplementedError('LocationWebPlugin is only for web platforms.');
  }

  void dispose() {
    // No-op
  }
}
