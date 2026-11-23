import 'package:alertabga/core/domain/incident_status.dart';
import 'package:alertabga/core/domain/report_models.dart';
import 'package:alertabga/core/theme/app_theme.dart';
import 'package:alertabga/features/auth/presentation/register_screen.dart';
import 'package:alertabga/features/auth/presentation/welcome_screen.dart';
import 'package:alertabga/features/emergency/emergency_screen.dart';
import 'package:alertabga/features/tracking/widgets/status_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Widget app(Widget child) => ProviderScope(child: MaterialApp(theme: AppTheme.light(), home: child));

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));

  testWidgets('bienvenida: Ingresar, Crear cuenta, Reportar sin cuenta, Consultar radicado y aviso 123', (t) async {
    await t.pumpWidget(app(const WelcomeScreen()));
    for (final label in ['Ingresar', 'Crear cuenta', 'Reportar sin cuenta', 'Consultar radicado']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await t.scrollUntilVisible(find.textContaining('123'), 200);
    expect(find.textContaining('123'), findsOneWidget);
  });

  testWidgets('registro valida correo, contraseña ≥ 8 y confirmación', (t) async {
    await t.pumpWidget(app(const RegisterScreen()));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), 'Ana Pérez');
    await t.enterText(fields.at(1), 'correo-malo');
    await t.enterText(fields.at(2), 'corta');
    await t.enterText(fields.at(3), 'otra');
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await t.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await t.pump();
    expect(find.text('Correo no válido'), findsOneWidget);
    expect(find.text('Mínimo 8 caracteres'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  testWidgets('registro exige aceptar el tratamiento de datos', (t) async {
    await t.pumpWidget(app(const RegisterScreen()));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), 'Ana Pérez');
    await t.enterText(fields.at(1), 'ana@example.com');
    await t.enterText(fields.at(2), 'Clave-Segura-1');
    await t.enterText(fields.at(3), 'Clave-Segura-1');
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await t.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await t.pump();
    expect(find.textContaining('Debe aceptar'), findsOneWidget);
  });

  testWidgets('StatusTimeline muestra mensajes institucionales y estados, lo reciente arriba', (t) async {
    await t.pumpWidget(app(Scaffold(
      body: StatusTimeline(entries: [
        TimelineEntry(at: DateTime.utc(2026, 11, 22, 10), kind: TimelineKind.status, status: IncidentStatus.recibido, text: 'Reporte recibido'),
        TimelineEntry(at: DateTime.utc(2026, 11, 22, 11), kind: TimelineKind.message, text: 'Una patrulla verificó el sector'),
      ]),
    )));
    expect(find.text('Mensaje de la institución'), findsOneWidget);
    expect(find.text('Una patrulla verificó el sector'), findsOneWidget);
    expect(find.text('Estado: Recibido'), findsOneWidget);
    final msgY = t.getTopLeft(find.text('Mensaje de la institución')).dy;
    final stY = t.getTopLeft(find.text('Estado: Recibido')).dy;
    expect(msgY < stY, isTrue);
  });

  testWidgets('StatusChip y StatusProgress muestran texto, no solo color', (t) async {
    await t.pumpWidget(app(const Scaffold(body: Column(children: [StatusChip(IncidentStatus.enAtencion), StatusProgress(IncidentStatus.enAtencion)]))));
    expect(find.text('En atención'), findsWidgets);
    expect(find.byIcon(IncidentStatus.enAtencion.icon), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('paso 4 de 5')), findsOneWidget);
  });

  testWidgets('emergencias ofrece llamar al 123', (t) async {
    await t.pumpWidget(app(const EmergencyScreen()));
    expect(find.text('Llamar al 123'), findsOneWidget);
    expect(find.text('155'), findsOneWidget);
  });
}
