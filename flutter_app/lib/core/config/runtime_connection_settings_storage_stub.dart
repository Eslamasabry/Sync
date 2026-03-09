import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage_types.dart';

class FileRuntimeConnectionSettingsStorage
    implements RuntimeConnectionSettingsStorage {
  const FileRuntimeConnectionSettingsStorage({Object? baseDirectory});

  @override
  Future<void> clear() async {}

  @override
  Future<RuntimeConnectionSettings?> load() async => null;

  @override
  Future<void> store(RuntimeConnectionSettings settings) async {}
}
