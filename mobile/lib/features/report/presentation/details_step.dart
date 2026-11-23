import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/report_controller.dart';

class DetailsStep extends ConsumerStatefulWidget {
  const DetailsStep({super.key, required this.anonymous});

  final bool anonymous;

  @override
  ConsumerState<DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends ConsumerState<DetailsStep> {
  late final TextEditingController _desc;
  late final TextEditingController _extra;
  late final TextEditingController _address;

  ReportController get _c => ref.read(reportControllerProvider(widget.anonymous).notifier);

  @override
  void initState() {
    super.initState();
    final d = ref.read(reportControllerProvider(widget.anonymous)).draft;
    _desc = TextEditingController(text: d.description);
    _extra = TextEditingController(text: d.additionalInfo);
    _address = TextEditingController(text: d.addressText);
  }

  @override
  void dispose() {
    _desc.dispose();
    _extra.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(DateTime current) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: 'Fecha del hecho',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current), helpText: 'Hora del hecho');
    if (time == null) return;
    var picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isAfter(now)) picked = now;
    _c.update((d) => d.copyWith(occurredAt: picked));
  }

  @override
  Widget build(BuildContext context) {
    final occurred = ref.watch(reportControllerProvider(widget.anonymous).select((s) => s.draft.occurredAt)) ?? DateTime.now();
    final fmt = DateFormat("EEEE d 'de' MMMM, h:mm a", 'es_CO');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('descripcion'),
          controller: _desc,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Describa lo ocurrido *',
            hintText: 'Qué pasó, cuántas personas, señas visibles, hacia dónde huyeron…',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _c.update((d) => d.copyWith(description: v)),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Fecha y hora del hecho'),
            subtitle: Text(fmt.format(occurred)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _pickDateTime(occurred),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _address,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Dirección o referencia (opcional)',
            hintText: 'Ej.: Calle 36 con Carrera 19, frente al parque',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _c.update((d) => d.copyWith(addressText: v)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _extra,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Información adicional (opcional)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _c.update((d) => d.copyWith(additionalInfo: v)),
        ),
      ],
    );
  }
}
