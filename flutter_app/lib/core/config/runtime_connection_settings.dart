class RuntimeConnectionSettings {
  const RuntimeConnectionSettings({
    required this.apiBaseUrl,
    required this.projectId,
    required this.authToken,
  });

  final String apiBaseUrl;
  final String projectId;
  final String authToken;

  String get normalizedApiBaseUrl => apiBaseUrl.trim();

  String get normalizedProjectId => projectId.trim();

  bool get hasAuthToken => authToken.trim().isNotEmpty;

  bool get isLocalhostTarget {
    final uri = Uri.tryParse(normalizedApiBaseUrl);
    if (uri == null) {
      return false;
    }

    switch (uri.host) {
      case 'localhost':
      case '127.0.0.1':
      case '::1':
        return true;
    }
    return false;
  }

  bool get usesHttp {
    final uri = Uri.tryParse(normalizedApiBaseUrl);
    return uri?.scheme == 'http';
  }

  String get shortHost {
    final uri = Uri.tryParse(normalizedApiBaseUrl);
    if (uri == null || uri.host.isEmpty) {
      return normalizedApiBaseUrl;
    }
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  String get identityKey =>
      '${normalizedApiBaseUrl.toLowerCase()}|$normalizedProjectId';

  RuntimeConnectionSettings copyWith({
    String? apiBaseUrl,
    String? projectId,
    String? authToken,
  }) {
    return RuntimeConnectionSettings(
      apiBaseUrl: apiBaseUrl ?? normalizedApiBaseUrl,
      projectId: projectId ?? normalizedProjectId,
      authToken: authToken ?? this.authToken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'api_base_url': apiBaseUrl,
      'project_id': projectId,
      'auth_token': authToken,
    };
  }

  static RuntimeConnectionSettings fromJson(Map<String, dynamic> json) {
    return RuntimeConnectionSettings(
      apiBaseUrl: json['api_base_url']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      authToken: json['auth_token']?.toString() ?? '',
    );
  }
}
