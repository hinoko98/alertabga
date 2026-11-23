import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../data/report_repository.dart';
import '../domain/report_draft.dart';

class ReportFormState {
  const ReportFormState({
    this.draft = const ReportDraft(),
    this.step = ReportStep.category,
    this.submitting = false,
    this.error,
    this.result,
  });

  final ReportDraft draft;
  final ReportStep step;
  final bool submitting;
  final String? error;
  final SubmitResult? result;

  ReportFormState copyWith({
    ReportDraft? draft,
    ReportStep? step,
    bool? submitting,
    String? Function()? error,
    SubmitResult? result,
  }) =>
      ReportFormState(
        draft: draft ?? this.draft,
        step: step ?? this.step,
        submitting: submitting ?? this.submitting,
        error: error != null ? error() : this.error,
        result: result ?? this.result,
      );

  /// El botón de envío solo se habilita con un borrador válido y sin envío en curso.
  bool get canSubmit => !submitting && result == null && draft.validate().isEmpty;
}

/// Controlador del asistente. El argumento indica si el reporte es anónimo.
class ReportController extends Notifier<ReportFormState> {
  ReportController(this.anonymous);

  final bool anonymous;

  @override
  ReportFormState build() => ReportFormState(draft: ReportDraft(occurredAt: DateTime.now()));

  void update(ReportDraft Function(ReportDraft d) change) =>
      state = state.copyWith(draft: change(state.draft), error: () => null);

  void goTo(ReportStep step) => state = state.copyWith(step: step, error: () => null);

  /// Avanza si el paso actual es válido; si no, deja el error visible.
  bool next() {
    final err = state.draft.validate()[state.step];
    if (err != null) {
      state = state.copyWith(error: () => err);
      return false;
    }
    final i = state.step.index;
    if (i < ReportStep.values.length - 1) goTo(ReportStep.values[i + 1]);
    return true;
  }

  void back() {
    final i = state.step.index;
    if (i > 0) goTo(ReportStep.values[i - 1]);
  }

  void addPhoto(PhotoAttachment p) {
    if (state.draft.photos.length >= maxPhotos) {
      state = state.copyWith(error: () => 'Máximo $maxPhotos fotos por reporte.');
      return;
    }
    if (p.size > maxPhotoBytes) {
      state = state.copyWith(error: () => 'La foto supera 5 MB. Elija otra o tómela con menor resolución.');
      return;
    }
    if (!allowedPhotoMime.contains(p.mime)) {
      state = state.copyWith(error: () => 'Formato no admitido. Use JPG, PNG o WEBP.');
      return;
    }
    update((d) => d.copyWith(photos: [...d.photos, p]));
  }

  void removePhoto(int index) =>
      update((d) => d.copyWith(photos: [...d.photos]..removeAt(index)));

  Future<SubmitResult?> submit() async {
    if (state.submitting || state.result != null) return null; // evita doble envío por doble toque
    final errors = state.draft.validate();
    if (errors.isNotEmpty) {
      final first = errors.entries.first;
      state = state.copyWith(step: first.key, error: () => first.value);
      return null;
    }
    state = state.copyWith(submitting: true, error: () => null);
    try {
      final r = await ref.read(reportRepositoryProvider).submit(state.draft, anonymous: anonymous);
      state = state.copyWith(submitting: false, result: r);
      return r;
    } catch (e) {
      state = state.copyWith(submitting: false, error: () => ApiError.from(e).message);
      return null;
    }
  }
}

final reportControllerProvider =
    NotifierProvider.autoDispose.family<ReportController, ReportFormState, bool>(ReportController.new);
