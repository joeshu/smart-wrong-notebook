// Compatibility entrypoint for the application's Riverpod providers.
// Keep existing imports of `src/app/providers.dart` working while concrete
// provider definitions live in responsibility-focused modules.
export 'providers/repository_providers.dart';
export 'providers/service_providers.dart';
export 'providers/capture_providers.dart';
export '../features/capture/application/capture_session_provider.dart';
export 'providers/review_providers.dart';
export 'providers/worksheet_providers.dart';
export 'providers/settings_providers.dart';
