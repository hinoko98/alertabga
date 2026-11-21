import 'package:alertabga/app.dart';
import 'package:alertabga/core/config/env.dart';
import 'package:alertabga/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env', () {
    test('reporta todas las claves faltantes', () {
      expect(Env.missing(url: '', anonKey: '', api: ''),
          ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'API_BASE_URL']);
    });

    test('vacío cuando la configuración está completa', () {
      expect(Env.missing(url: 'http://x', anonKey: 'k', api: 'http://api'), isEmpty);
    });
  });

  test('tema usa el azul institucional como primario', () {
    expect(AppTheme.light().colorScheme.primary, BrandColors.navy900);
  });

  testWidgets('sin configuración muestra el aviso explícito', (tester) async {
    await tester.pumpWidget(const MissingConfigApp(missing: ['SUPABASE_URL']));
    expect(find.textContaining('Configuración incompleta: SUPABASE_URL'), findsOneWidget);
  });
}
