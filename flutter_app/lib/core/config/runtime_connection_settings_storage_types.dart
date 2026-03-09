import 'package:sync_flutter/core/config/runtime_connection_settings.dart';

abstract class RuntimeConnectionSettingsStorage {
  const RuntimeConnectionSettingsStorage();

  Future<RuntimeConnectionSettings?> load();

  Future<void> store(RuntimeConnectionSettings settings);

  Future<void> clear();
}
