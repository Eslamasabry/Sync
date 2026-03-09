class RuntimeConnectionSettings {
  const RuntimeConnectionSettings({
    required this.apiBaseUrl,
    required this.projectId,
    required this.authToken,
  });

  final String apiBaseUrl;
  final String projectId;
  final String authToken;

  bool get hasAuthToken => authToken.trim().isNotEmpty;

  RuntimeConnectionSettings copyWith({
    String? apiBaseUrl,
    String? projectId,
    String? authToken,
  }) {
    return RuntimeConnectionSettings(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      projectId: projectId ?? this.projectId,
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
