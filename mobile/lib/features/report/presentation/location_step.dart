import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/location_service.dart';
import '../../../core/geo/territorial_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../application/report_controller.dart';
import '../domain/report_draft.dart';

const osmUserAgent = 'co.gov.alertabga.alertabga';

class LocationStep extends ConsumerStatefulWidget {
  const LocationStep({super.key, required this.anonymous});

  final bool anonymous;

  @override
  ConsumerState<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends ConsumerState<LocationStep> {
  final _map = MapController();
  bool _locating = false;
  LocationFailure? _failure;

  ReportController get _c => ref.read(reportControllerProvider(widget.anonymous).notifier);

  @override
  void initState() {
    super.initState();
    final loc = ref.read(reportControllerProvider(widget.anonymous)).draft.location;
    if (loc == null) WidgetsBinding.instance.addPostFrameCallback((_) => _useGps());
  }

  Future<void> _useGps() async {
    setState(() {
      _locating = true;
      _failure = null;
    });
    try {
      final fix = await ref.read(locationServiceProvider).current();
      _c.update((d) => d.copyWith(location: ReportLocation(lat: fix.lat, lon: fix.lon, accuracyM: fix.accuracyM, manual: false)));
      _map.move(LatLng(fix.lat, fix.lon), 17);
    } on LocationFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _pick(LatLng p) =>
      _c.update((d) => d.copyWith(location: ReportLocation(lat: p.latitude, lon: p.longitude, manual: true)));

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(reportControllerProvider(widget.anonymous).select((s) => s.draft.location));
    const scope = TerritorialScope.bucaramanga;
    final point = loc == null ? null : LatLng(loc.lat, loc.lon);
    final outside = loc != null && !scope.contains(loc.lat, loc.lon);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Toque el mapa para marcar o corregir el lugar exacto del hecho.'),
              if (_failure != null) ...[
                const SizedBox(height: 8),
                ErrorBox(_failure!.message),
                if (_failure!.canOpenSettings)
                  TextButton(
                      onPressed: () => ref.read(locationServiceProvider).openSettings(),
                      child: const Text('Abrir ajustes de ubicación')),
              ],
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: point ?? scope.initialCenter,
                  initialZoom: point == null ? 13 : 17,
                  onTap: (_, p) => _pick(p),
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: osmUserAgent),
                  if (point != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: point,
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_pin, size: 48, color: BrandColors.danger, semanticLabel: 'Lugar del hecho'),
                      ),
                    ]),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
                ],
              ),
              Positioned(
                right: 12,
                top: 12,
                child: FloatingActionButton.extended(
                  heroTag: 'gps',
                  onPressed: _locating ? null : _useGps,
                  icon: _locating
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                  label: Text(_locating ? 'Ubicando…' : 'Mi ubicación'),
                ),
              ),
            ],
          ),
        ),
        if (loc != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(outside ? Icons.wrong_location_outlined : Icons.check_circle_outline,
                    color: outside ? BrandColors.danger : BrandColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    outside
                        ? 'Fuera de ${scope.name}: no se puede enviar.'
                        : loc.manual
                            ? 'Ubicación marcada en el mapa'
                            : 'Ubicación GPS (precisión ±${loc.accuracyM?.round() ?? '?'} m)',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
