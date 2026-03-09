import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage.dart';

final runtimeConnectionSettingsStorageProvider =
    Provider<RuntimeConnectionSettingsStorage>(
      (ref) => const FileRuntimeConnectionSettingsStorage(),
    );

final runtimeConnectionSettingsRevisionProvider =
    NotifierProvider<RuntimeConnectionSettingsRevisionController, int>(
      RuntimeConnectionSettingsRevisionController.new,
    );

class RuntimeConnectionSettingsRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state += 1;
  }
}

final recentRuntimeConnectionSettingsProvider =
    FutureProvider<List<RuntimeConnectionSettings>>((ref) async {
      ref.watch(runtimeConnectionSettingsRevisionProvider);
      return ref.watch(runtimeConnectionSettingsStorageProvider).loadRecent();
    });

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
    ref.read(runtimeConnectionSettingsRevisionProvider.notifier).bump();
  }

  Future<void> removeRecent(RuntimeConnectionSettings settings) async {
    final current = state.asData?.value;
    if (current != null && current.identityKey == settings.identityKey) {
      state = const AsyncData(defaultConnectionSettings);
    }
    await ref.watch(runtimeConnectionSettingsStorageProvider).remove(settings);
    ref.read(runtimeConnectionSettingsRevisionProvider.notifier).bump();
  }

  Future<void> reset() async {
    state = const AsyncData(defaultConnectionSettings);
    await ref.watch(runtimeConnectionSettingsStorageProvider).clear();
    ref.read(runtimeConnectionSettingsRevisionProvider.notifier).bump();
  }
}
