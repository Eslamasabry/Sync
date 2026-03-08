const defaultProjectId = String.fromEnvironment(
  'SYNC_PROJECT_ID',
  defaultValue: 'demo-book',
);

const defaultApiBaseUrl = String.fromEnvironment(
  'SYNC_API_BASE_URL',
  defaultValue: 'http://localhost:8000/v1',
);
