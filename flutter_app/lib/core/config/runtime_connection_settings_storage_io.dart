import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage_types.dart';

class FileRuntimeConnectionSettingsStorage
    implements RuntimeConnectionSettingsStorage {
  const FileRuntimeConnectionSettingsStorage({this.baseDirectory});

  final Directory? baseDirectory;
  static const _maxRecentConnections = 5;

  @override
  Future<RuntimeConnectionSettings?> load() async {
    final payload = await _readPayload();
    if (payload == null) {
      return null;
    }

    final activePayload = payload['active_settings'];
    if (activePayload is Map) {
      return RuntimeConnectionSettings.fromJson(
        Map<String, dynamic>.from(activePayload),
      );
    }

    // Backward compatibility for the original single-settings file format.
    if (payload.containsKey('api_base_url')) {
      return RuntimeConnectionSettings.fromJson(payload);
    }
    return null;
  }

  @override
  Future<List<RuntimeConnectionSettings>> loadRecent() async {
    final payload = await _readPayload();
    if (payload == null) {
      return const [];
    }

    final recentPayload = payload['recent_connections'];
    if (recentPayload is! List) {
      return const [];
    }

    return [
      for (final item in recentPayload)
        if (item is Map)
          RuntimeConnectionSettings.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  @override
  Future<void> store(RuntimeConnectionSettings settings) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    final recent = await loadRecent();
    final mergedRecent = [
      settings,
      for (final item in recent)
        if (item.identityKey != settings.identityKey) item,
    ].take(_maxRecentConnections).toList(growable: false);

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'active_settings': settings.toJson(),
        'recent_connections': [for (final item in mergedRecent) item.toJson()],
      }),
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

  Future<Map<String, dynamic>?> _readPayload() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }

    final payload = jsonDecode(await file.readAsString());
    if (payload is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(payload);
  }

  Future<Directory> _settingsRoot() async {
    if (baseDirectory != null) {
      return baseDirectory!;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/sync_runtime_config');
  }
}
