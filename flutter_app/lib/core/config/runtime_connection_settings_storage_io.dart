import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage_types.dart';

class FileRuntimeConnectionSettingsStorage
    implements RuntimeConnectionSettingsStorage {
  const FileRuntimeConnectionSettingsStorage({this.baseDirectory});

  final Directory? baseDirectory;

  @override
  Future<RuntimeConnectionSettings?> load() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }

    final payload = jsonDecode(await file.readAsString());
    if (payload is! Map) {
      return null;
    }

    return RuntimeConnectionSettings.fromJson(
      Map<String, dynamic>.from(payload),
    );
  }

  @override
  Future<void> store(RuntimeConnectionSettings settings) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  @override
  Future<void> clear() async {
    final file = await _settingsFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _settingsFile() async {
    final root = await _settingsRoot();
    return File('${root.path}/runtime_connection_settings.json');
  }

  Future<Directory> _settingsRoot() async {
    if (baseDirectory != null) {
      return baseDirectory!;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/sync_runtime_config');
  }
}
