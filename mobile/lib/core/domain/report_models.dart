import 'incident_status.dart';

class Category {
  const Category({required this.id, required this.name, required this.description, required this.icon});

  final String id;
  final String name;
  final String description;
  final String icon;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        description: (j['description'] as String?) ?? '',
        icon: (j['icon'] as String?) ?? '',
      );
}

class ReportCreated {
  const ReportCreated({
    required this.id,
    required this.radicado,
    required this.receivedAt,
    required this.outOfScope,
    this.trackingToken,
  });

  final String id;
  final String radicado;
  final DateTime receivedAt;
  final bool outOfScope;
  final String? trackingToken;

  factory ReportCreated.fromJson(Map<String, dynamic> j) => ReportCreated(
        id: j['id'] as String,
        radicado: j['radicado'] as String,
        receivedAt: DateTime.parse(j['received_at'] as String),
        outOfScope: (j['out_of_scope'] as bool?) ?? false,
        trackingToken: j['tracking_token'] as String?,
      );
}

class ReportSummary {
  const ReportSummary({required this.radicado, required this.category, required this.status, required this.receivedAt});

  final String radicado;
  final String category;
  final IncidentStatus status;
  final DateTime receivedAt;

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        radicado: j['radicado'] as String,
        category: j['category'] as String,
        status: IncidentStatus.fromCode(j['status'] as String?),
        receivedAt: DateTime.parse(j['received_at'] as String),
      );
}

enum TimelineKind { status, message }

class TimelineEntry {
  const TimelineEntry({required this.at, required this.kind, this.status, this.text});

  final DateTime at;
  final TimelineKind kind;
  final IncidentStatus? status;
  final String? text;

  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
        at: DateTime.parse(j['at'] as String),
        kind: j['kind'] == 'mensaje' ? TimelineKind.message : TimelineKind.status,
        status: j['status'] == null ? null : IncidentStatus.fromCode(j['status'] as String),
        text: j['text'] as String?,
      );
}

class ReportDetail {
  const ReportDetail({
    required this.id,
    required this.radicado,
    required this.category,
    required this.status,
    required this.description,
    required this.occurredAt,
    required this.receivedAt,
    required this.addressText,
    required this.outOfScope,
    required this.evidenceCount,
    required this.timeline,
  });

  final String id;
  final String radicado;
  final String category;
  final IncidentStatus status;
  final String description;
  final DateTime occurredAt;
  final DateTime receivedAt;
  final String? addressText;
  final bool outOfScope;
  final int evidenceCount;
  final List<TimelineEntry> timeline;

  factory ReportDetail.fromJson(Map<String, dynamic> j) => ReportDetail(
        id: j['id'] as String,
        radicado: j['radicado'] as String,
        category: j['category'] as String,
        status: IncidentStatus.fromCode(j['status'] as String?),
        description: j['description'] as String,
        occurredAt: DateTime.parse(j['occurred_at'] as String),
        receivedAt: DateTime.parse(j['received_at'] as String),
        addressText: j['address_text'] as String?,
        outOfScope: (j['out_of_scope'] as bool?) ?? false,
        evidenceCount: (j['evidence_count'] as num?)?.toInt() ?? 0,
        timeline: [
          for (final e in (j['timeline'] as List? ?? const [])) TimelineEntry.fromJson(e as Map<String, dynamic>),
        ],
      );
}

class PresignedUpload {
  const PresignedUpload({required this.evidenceId, required this.uploadUrl, required this.headers});

  final String evidenceId;
  final String uploadUrl;
  final Map<String, String> headers;

  factory PresignedUpload.fromJson(Map<String, dynamic> j) => PresignedUpload(
        evidenceId: j['evidence_id'] as String,
        uploadUrl: j['upload_url'] as String,
        headers: (j['headers'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v')),
      );
}
