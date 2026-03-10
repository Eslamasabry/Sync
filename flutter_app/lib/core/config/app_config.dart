import 'package:sync_flutter/core/config/runtime_connection_settings.dart';

const defaultProjectId = String.fromEnvironment(
  'SYNC_PROJECT_ID',
  defaultValue: '',
);

const defaultApiBaseUrl = String.fromEnvironment(
  'SYNC_API_BASE_URL',
  defaultValue: 'http://localhost:8000/v1',
);

const defaultApiAuthToken = String.fromEnvironment(
  'SYNC_API_AUTH_TOKEN',
  defaultValue: '',
);

const defaultConnectionSettings = RuntimeConnectionSettings(
  apiBaseUrl: defaultApiBaseUrl,
  projectId: defaultProjectId,
  authToken: defaultApiAuthToken,
);
