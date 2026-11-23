import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LocationFailure implements Exception {
  const LocationFailure(this.message, {this.canOpenSettings = false});

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}

class GpsFix {
  const GpsFix(this.lat, this.lon, this.accuracyM);

  final double lat;
  final double lon;
  final double accuracyM;
}

/// Obtiene la ubicación actual. Si el GPS está apagado o el permiso se niega, lanza
/// [LocationFailure] y la app ofrece marcar el punto en el mapa.
class LocationService {
  const LocationService();

  Future<GpsFix> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure('La ubicación del teléfono está apagada. Actívela o marque el lugar en el mapa.',
          canOpenSettings: true);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) {
      throw const LocationFailure('Sin permiso de ubicación. Puede marcar el lugar en el mapa.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw const LocationFailure('El permiso de ubicación está bloqueado. Habilítelo en Ajustes o marque el lugar en el mapa.',
          canOpenSettings: true);
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return GpsFix(p.latitude, p.longitude, p.accuracy);
    } catch (_) {
      throw const LocationFailure('No se pudo obtener la ubicación. Marque el lugar en el mapa.');
    }
  }

  Future<void> openSettings() async {
    if (!await Geolocator.openLocationSettings()) await Geolocator.openAppSettings();
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => const LocationService());
