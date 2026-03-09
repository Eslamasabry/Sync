import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage.dart';

final runtimeConnectionSettingsStorageProvider =
    Provider<RuntimeConnectionSettingsStorage>(
      (ref) => const FileRuntimeConnectionSettingsStorage(),
    );

final runtimeConnectionSettingsProvider =
    AsyncNotifierProvider<
      RuntimeConnectionSettingsController,
      RuntimeConnectionSettings
    >(RuntimeConnectionSettingsController.new);

class RuntimeConnectionSettingsController
    extends AsyncNotifier<RuntimeConnectionSettings> {
  @override
  Future<RuntimeConnectionSettings> build() async {
    final stored = await ref
        .watch(runtimeConnectionSettingsStorageProvider)
        .load();
    return stored ?? defaultConnectionSettings;
  }

  Future<void> save(RuntimeConnectionSettings settings) async {
    state = AsyncData(settings);
    await ref.watch(runtimeConnectionSettingsStorageProvider).store(settings);
  }

  Future<void> reset() async {
    state = const AsyncData(defaultConnectionSettings);
    await ref.watch(runtimeConnectionSettingsStorageProvider).clear();
  }
}
