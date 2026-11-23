import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/emergency/emergency_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/report/data/report_repository.dart';
import '../../features/report/presentation/confirmation_screen.dart';
import '../../features/report/presentation/report_flow_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/system/system_status_screen.dart';
import '../../features/tracking/presentation/track_lookup_screen.dart';
import '../../features/tracking/presentation/tracking_screen.dart';

const _authOnly = {'/home', '/reports'};
const _guestOnly = {'/', '/login', '/register', '/forgot-password'};

/// Decide la redirección según la sesión. Pura para poder probarla.
String? authRedirect({required String path, required bool signedIn, required bool recovering}) {
  if (recovering && signedIn) return path == '/reset-password' ? null : '/reset-password';
  if (!signedIn && _authOnly.any((p) => path == p || path.startsWith('$p/'))) return '/';
  if (signedIn && _guestOnly.contains(path)) return '/home';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionStateProvider);
  final router = GoRouter(
    refreshListenable: session,
    redirect: (context, state) =>
        authRedirect(path: state.matchedLocation, signedIn: session.signedIn, recovering: session.recovering),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
      GoRoute(
        path: '/report',
        // Sin sesión siempre es anónimo, aunque se pida lo contrario.
        builder: (_, s) => ReportFlowScreen(anonymous: !session.signedIn || s.extra != false),
      ),
      GoRoute(path: '/report/done', builder: (_, s) => ConfirmationScreen(result: s.extra! as SubmitResult)),
      GoRoute(path: '/track', builder: (_, _) => const TrackLookupScreen()),
      GoRoute(path: '/track/view', builder: (_, s) {
        final (radicado, token) = s.extra! as (String, String);
        return TrackingScreen.anonymous(radicado: radicado, token: token);
      }),
      GoRoute(path: '/reports/:radicado', builder: (_, s) => TrackingScreen.own(radicado: s.pathParameters['radicado']!)),
      GoRoute(path: '/emergency', builder: (_, _) => const EmergencyScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/system', builder: (_, _) => const SystemStatusScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
