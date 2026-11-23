import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../application/report_controller.dart';
import '../domain/report_draft.dart';

class PhotosStep extends ConsumerStatefulWidget {
  const PhotosStep({super.key, required this.anonymous});

  final bool anonymous;

  @override
  ConsumerState<PhotosStep> createState() => _PhotosStepState();
}

class _PhotosStepState extends ConsumerState<PhotosStep> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    setState(() => _busy = true);
    try {
      // Redimensionar re-codifica la imagen: reduce el peso y descarta la mayoría de metadatos EXIF.
      final file = await _picker.pickImage(source: source, maxWidth: 1920, maxHeight: 1920, imageQuality: 82);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? mimeForPath(file.name) ?? mimeForPath(file.path) ?? 'image/jpeg';
      ref.read(reportControllerProvider(widget.anonymous).notifier)
          .addPhoto(PhotoAttachment(name: file.name, mime: mime, bytes: bytes));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo obtener la foto.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(reportControllerProvider(widget.anonymous).select((s) => s.draft.photos));
    final c = ref.read(reportControllerProvider(widget.anonymous).notifier);
    final full = photos.length >= maxPhotos;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: BrandColors.amber, semanticLabel: 'Advertencia'),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Su seguridad es primero. No persiga, no confronte ni se exponga para tomar fotos. '
                  'Adjunte solo imágenes que ya tenga o que pueda tomar sin riesgo.',
                  style: TextStyle(color: Color(0xFF78350F), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('${photos.length} de $maxPhotos fotos · máximo 5 MB cada una', style: const TextStyle(color: BrandColors.slate500)),
        const SizedBox(height: 12),
        if (photos.isNotEmpty)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(photos[i].bytes, fit: BoxFit.cover)),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: IconButton.filled(
                        tooltip: 'Quitar foto',
                        style: IconButton.styleFrom(backgroundColor: Colors.black54),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => c.removePhoto(i),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: full || _busy ? null : () => _pick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Tomar foto'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: full || _busy ? null : () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Elegir de la galería'),
        ),
        const SizedBox(height: 12),
        const Text('Las fotos se guardan de forma privada: solo las ve el personal autorizado.',
            style: TextStyle(color: BrandColors.slate500)),
      ],
    );
  }
}
