import 'package:latlong2/latlong.dart';

/// Ámbito territorial donde se aceptan reportes (caja envolvente aproximada del municipio).
/// Coincide con `app_settings.territorial_scope` del servidor, que de todos modos marca `out_of_scope`.
class TerritorialScope {
  const TerritorialScope({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.name,
  });

  static const bucaramanga = TerritorialScope(
    minLat: 7.03,
    maxLat: 7.25,
    minLon: -73.20,
    maxLon: -73.03,
    name: 'Bucaramanga',
  );

  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final String name;

  bool contains(double lat, double lon) => lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  /// Centro del Parque Santander, punto inicial del mapa cuando no hay GPS.
  LatLng get initialCenter => const LatLng(7.1193, -73.1227);
}
