import 'dart:typed_data';

import '../../../core/domain/report_models.dart';
import '../../../core/geo/territorial_scope.dart';

const maxPhotos = 3;
const maxPhotoBytes = 5 * 1024 * 1024;
const allowedPhotoMime = {'image/jpeg', 'image/png', 'image/webp'};

String? mimeForPath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  return null;
}

class PhotoAttachment {
  const PhotoAttachment({required this.name, required this.mime, required this.bytes});

  final String name;
  final String mime;
  final Uint8List bytes;

  int get size => bytes.length;
}

class ReportLocation {
  const ReportLocation({required this.lat, required this.lon, this.accuracyM, required this.manual});

  final double lat;
  final double lon;
  final double? accuracyM;
  final bool manual;
}

/// Pasos del asistente de reporte.
enum ReportStep { category, location, details, photos, review }

/// Borrador inmutable del reporte. `validate` devuelve los errores por paso (vacío = listo).
class ReportDraft {
  const ReportDraft({
    this.category,
    this.location,
    this.description = '',
    this.additionalInfo = '',
    this.addressText = '',
    this.occurredAt,
    this.photos = const [],
  });

  final Category? category;
  final ReportLocation? location;
  final String description;
  final String additionalInfo;
  final String addressText;
  final DateTime? occurredAt;
  final List<PhotoAttachment> photos;

  ReportDraft copyWith({
    Category? category,
    ReportLocation? location,
    String? description,
    String? additionalInfo,
    String? addressText,
    DateTime? occurredAt,
    List<PhotoAttachment>? photos,
  }) =>
      ReportDraft(
        category: category ?? this.category,
        location: location ?? this.location,
        description: description ?? this.description,
        additionalInfo: additionalInfo ?? this.additionalInfo,
        addressText: addressText ?? this.addressText,
        occurredAt: occurredAt ?? this.occurredAt,
        photos: photos ?? this.photos,
      );

  Map<ReportStep, String> validate({
    TerritorialScope scope = TerritorialScope.bucaramanga,
    DateTime? now,
  }) {
    final errors = <ReportStep, String>{};
    final n = now ?? DateTime.now();
    if (category == null) errors[ReportStep.category] = 'Seleccione el tipo de incidente.';

    final loc = location;
    if (loc == null) {
      errors[ReportStep.location] = 'Indique dónde ocurrió el hecho.';
    } else if (!scope.contains(loc.lat, loc.lon)) {
      errors[ReportStep.location] = 'La ubicación está fuera de ${scope.name}. Solo se reciben reportes dentro del municipio.';
    }

    final desc = description.trim();
    final occurred = occurredAt;
    if (desc.length < 10) {
      errors[ReportStep.details] = 'Describa lo ocurrido (mínimo 10 caracteres).';
    } else if (desc.length > 2000) {
      errors[ReportStep.details] = 'La descripción admite máximo 2000 caracteres.';
    } else if (additionalInfo.trim().length > 1000) {
      errors[ReportStep.details] = 'La información adicional admite máximo 1000 caracteres.';
    } else if (addressText.trim().length > 200) {
      errors[ReportStep.details] = 'La dirección admite máximo 200 caracteres.';
    } else if (occurred == null) {
      errors[ReportStep.details] = 'Indique la fecha y hora del hecho.';
    } else if (occurred.isAfter(n.add(const Duration(minutes: 5)))) {
      errors[ReportStep.details] = 'La fecha del hecho no puede ser futura.';
    }

    if (photos.length > maxPhotos) {
      errors[ReportStep.photos] = 'Máximo $maxPhotos fotos.';
    } else if (photos.any((p) => p.size > maxPhotoBytes || p.size == 0)) {
      errors[ReportStep.photos] = 'Cada foto debe pesar máximo 5 MB.';
    } else if (photos.any((p) => !allowedPhotoMime.contains(p.mime))) {
      errors[ReportStep.photos] = 'Solo se admiten fotos JPG, PNG o WEBP.';
    }
    return errors;
  }

  Map<String, dynamic> toRequest() {
    final loc = location!;
    String? opt(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      'category_id': category!.id,
      'description': description.trim(),
      'additional_info': opt(additionalInfo),
      'address_text': opt(addressText),
      'occurred_at': occurredAt!.toUtc().toIso8601String(),
      'lat': loc.lat,
      'lon': loc.lon,
      'accuracy_m': loc.accuracyM,
      'location_manual': loc.manual,
    };
  }
}
