import 'package:dio/dio.dart';
import 'package:sync_flutter/core/import/import_file_picker.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';

class ApiClientException implements Exception {
  const ApiClientException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class ProjectCreateResult {
  const ProjectCreateResult({
    required this.projectId,
    required this.status,
    this.createdAt,
  });

  final String projectId;
  final String status;
  final DateTime? createdAt;
}

class ProjectLifecycleInfo {
  const ProjectLifecycleInfo({
    required this.phase,
    required this.nextAction,
    required this.isReadable,
    required this.missingRequirements,
  });

  final String phase;
  final String nextAction;
  final bool isReadable;
  final List<String> missingRequirements;
}

class AssetUploadResult {
  const AssetUploadResult({
    required this.assetId,
    required this.status,
    required this.uploadMode,
  });

  final String assetId;
  final String status;
  final String uploadMode;
}

class AlignmentJobResult {
  const AlignmentJobResult({
    required this.jobId,
    required this.status,
    required this.reusedExisting,
    required this.attemptNumber,
    this.retryOfJobId,
    this.terminalReason,
    this.percent,
    this.stage,
  });

  final String jobId;
  final String status;
  final bool reusedExisting;
  final int attemptNumber;
  final String? retryOfJobId;
  final String? terminalReason;
  final int? percent;
  final String? stage;
}

class ProjectJobsResult {
  const ProjectJobsResult({required this.projectId, required this.jobs});

  final String projectId;
  final List<AlignmentJobResult> jobs;
}

class SyncApiErrorInfo {
  const SyncApiErrorInfo({required this.message, this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;
}

class ProjectListItem {
  const ProjectListItem({
    required this.projectId,
    required this.title,
    required this.status,
    required this.assetCount,
    required this.audioAssetCount,
    this.language,
    this.latestJob,
    this.lifecycle,
  });

  final String projectId;
  final String title;
  final String? language;
  final String status;
  final int assetCount;
  final int audioAssetCount;
  final AlignmentJobResult? latestJob;
  final ProjectLifecycleInfo? lifecycle;
}

class SyncApiClient {
  SyncApiClient({
    Dio? dio,
    String baseUrl = 'http://localhost:8000/v1',
    String authToken = '',
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _authToken = authToken.trim(),
       _dio = dio ?? Dio(BaseOptions(baseUrl: _normalizeBaseUrl(baseUrl))) {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.headers.addAll(_defaultHeaders(_authToken));
  }

  final String _baseUrl;
  final String _authToken;
  final Dio _dio;

  Future<ReaderModel> fetchReaderModel(String projectId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/projects/$projectId/reader-model',
      );
      final body = _asMap(response.data, context: 'reader model response');
      if (_looksLikeReaderModelPayload(body)) {
        return ReaderModel.fromJson(body);
      }

      final inlineModel = body['model'];
      if (inlineModel is Map<String, dynamic>) {
        return ReaderModel.fromJson(inlineModel);
      }
      if (inlineModel is Map) {
        return ReaderModel.fromJson(Map<String, dynamic>.from(inlineModel));
      }

      final downloadUrl = body['download_url']?.toString();
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        final downloadResponse = await _dio.getUri<Object?>(
          Uri.parse(downloadUrl),
        );
        return ReaderModel.fromJson(
          _asMap(downloadResponse.data, context: 'reader model download'),
        );
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message:
            'Reader model response did not include an inline model or download URL.',
        type: DioExceptionType.badResponse,
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<SyncArtifact> fetchSyncArtifact(String projectId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/projects/$projectId/sync',
      );
      final body = _asMap(response.data, context: 'sync artifact response');
      if (_looksLikeSyncPayload(body)) {
        return SyncArtifact.fromJson(body);
      }

      final inlinePayload = body['inline_payload'];
      if (inlinePayload is Map<String, dynamic>) {
        return SyncArtifact.fromJson(inlinePayload);
      }
      if (inlinePayload is Map) {
        return SyncArtifact.fromJson(Map<String, dynamic>.from(inlinePayload));
      }

      final downloadUrl = body['download_url']?.toString();
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        final downloadResponse = await _dio.getUri<Object?>(
          Uri.parse(downloadUrl),
        );
        return SyncArtifact.fromJson(
          _asMap(downloadResponse.data, context: 'sync artifact download'),
        );
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message:
            'Sync artifact response did not include inline payload or download URL.',
        type: DioExceptionType.badResponse,
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> fetchProjectDetail(String projectId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/projects/$projectId',
      );
      return _asMap(response.data, context: 'project detail response');
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<ProjectListItem>> fetchProjects() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/projects');
      final body = _asMap(response.data, context: 'project list response');
      return _asObjectList(body['projects'])
          .map((project) {
            final latestJob = _asMapOrNull(project['latest_job']);
            return ProjectListItem(
              projectId: project['project_id']?.toString() ?? '',
              title: project['title']?.toString() ?? 'Untitled project',
              language: project['language']?.toString(),
              status: project['status']?.toString() ?? 'unknown',
              assetCount: (project['asset_count'] as num?)?.round() ?? 0,
              audioAssetCount:
                  (project['audio_asset_count'] as num?)?.round() ?? 0,
              latestJob: latestJob == null ? null : _parseJobResult(latestJob),
              lifecycle: _parseLifecycle(project['lifecycle']),
            );
          })
          .toList(growable: false);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<ProjectCreateResult> createProject({
    required String title,
    required String language,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/projects',
        data: {'title': title, 'language': language},
      );
      final body = _asMap(response.data, context: 'project create response');
      return ProjectCreateResult(
        projectId: body['project_id']?.toString() ?? '',
        status: body['status']?.toString() ?? 'created',
        createdAt: DateTime.tryParse(body['created_at']?.toString() ?? ''),
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<AssetUploadResult> uploadAsset({
    required String projectId,
    required String kind,
    required ImportPickedFile file,
  }) async {
    MultipartFile multipartFile;
    if (file.path != null && file.path!.isNotEmpty) {
      multipartFile = await MultipartFile.fromFile(
        file.path!,
        filename: file.name,
      );
    } else if (file.bytes != null) {
      multipartFile = MultipartFile.fromBytes(file.bytes!, filename: file.name);
    } else {
      throw ArgumentError(
        'Import file must include a path or in-memory bytes.',
      );
    }

    final formData = FormData.fromMap({'kind': kind, 'file': multipartFile});
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/projects/$projectId/assets/upload',
        data: formData,
      );
      final body = _asMap(response.data, context: 'asset upload response');
      return AssetUploadResult(
        assetId: body['asset_id']?.toString() ?? '',
        status: body['status']?.toString() ?? 'uploaded',
        uploadMode: body['upload_mode']?.toString() ?? 'multipart',
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<AlignmentJobResult> createAlignmentJob({
    required String projectId,
    required String bookAssetId,
    required List<String> audioAssetIds,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/projects/$projectId/jobs',
        data: {
          'job_type': 'alignment',
          'book_asset_id': bookAssetId,
          'audio_asset_ids': audioAssetIds,
        },
      );
      return _parseJobResult(
        _asMap(response.data, context: 'alignment job response'),
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<AlignmentJobResult> fetchJob({
    required String projectId,
    required String jobId,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/projects/$projectId/jobs/$jobId',
      );
      return _parseJobResult(
        _asMap(response.data, context: 'job detail response'),
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<ProjectJobsResult> fetchProjectJobs(String projectId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/projects/$projectId/jobs',
      );
      final body = _asMap(response.data, context: 'project jobs response');
      final jobs = _asObjectList(
        body['jobs'],
      ).map(_parseJobResult).toList(growable: false);
      return ProjectJobsResult(
        projectId: body['project_id']?.toString() ?? projectId,
        jobs: jobs,
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<void> downloadFile({
    required String url,
    required String savePath,
    ProgressCallback? onReceiveProgress,
  }) {
    return _dio.download(
      url,
      savePath,
      onReceiveProgress: onReceiveProgress,
      deleteOnError: true,
    );
  }

  String assetContentUrl({required String projectId, required String assetId}) {
    return '$_baseUrl/projects/$projectId/assets/$assetId/content';
  }

  Map<String, String> get authorizationHeaders => _defaultHeaders(_authToken);

  AlignmentJobResult _parseJobResult(Map<String, dynamic> body) {
    final progress = body['progress'];
    final progressMap = progress is Map<String, dynamic>
        ? progress
        : progress is Map
        ? Map<String, dynamic>.from(progress)
        : const <String, dynamic>{};
    return AlignmentJobResult(
      jobId: body['job_id']?.toString() ?? '',
      status: body['status']?.toString() ?? 'unknown',
      reusedExisting: body['reused_existing'] == true,
      attemptNumber: (body['attempt_number'] as num?)?.round() ?? 1,
      retryOfJobId: body['retry_of_job_id']?.toString(),
      terminalReason: body['terminal_reason']?.toString(),
      percent: (progressMap['percent'] as num?)?.round(),
      stage: progressMap['stage']?.toString(),
    );
  }

  ProjectLifecycleInfo? _parseLifecycle(Object? value) {
    final body = _asMapOrNull(value);
    if (body == null) {
      return null;
    }
    return ProjectLifecycleInfo(
      phase: body['phase']?.toString() ?? 'unknown',
      nextAction: body['next_action']?.toString() ?? 'review',
      isReadable: body['is_readable'] == true,
      missingRequirements: _asStringList(body['missing_requirements']),
    );
  }
}

String _normalizeBaseUrl(String baseUrl) {
  return baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
}

Map<String, dynamic> _asMap(Object? value, {required String context}) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw FormatException('Expected JSON object for $context.');
}

List<Map<String, dynamic>> _asObjectList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .map((item) => _asMap(item, context: 'object list item'))
      .toList(growable: false);
}

List<String> _asStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

Map<String, dynamic>? _asMapOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _asMap(value, context: 'optional object');
}

bool _looksLikeSyncPayload(Map<String, dynamic> payload) {
  return payload.containsKey('book_id') && payload.containsKey('tokens');
}

bool _looksLikeReaderModelPayload(Map<String, dynamic> payload) {
  return payload.containsKey('book_id') &&
      payload.containsKey('title') &&
      payload.containsKey('sections');
}

Map<String, String> _defaultHeaders(String authToken) {
  if (authToken.isEmpty) {
    return const {};
  }
  return {'Authorization': 'Bearer $authToken'};
}

ApiClientException _mapDioException(DioException error) {
  final responseBody = error.response?.data;
  final body = responseBody is Map<String, dynamic>
      ? responseBody
      : responseBody is Map
      ? Map<String, dynamic>.from(responseBody)
      : null;
  final errorEnvelope = _asMapOrNull(body?['error']);
  final code = errorEnvelope?['code']?.toString();
  final apiMessage = errorEnvelope?['message']?.toString();

  if (apiMessage != null && apiMessage.isNotEmpty) {
    return ApiClientException(apiMessage, code: code);
  }

  switch (error.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return const ApiClientException(
        'Could not reach the Sync server. Check the server URL and network first.',
      );
    case DioExceptionType.badResponse:
      if (error.response?.statusCode == 401) {
        return const ApiClientException(
          'The server rejected the token. Update the auth token and try again.',
          code: 'auth_invalid',
        );
      }
      if (error.response?.statusCode == 404) {
        return const ApiClientException(
          'That project or artifact does not exist on the server yet.',
        );
      }
      return ApiClientException(
        error.message ?? 'The server returned an unexpected response.',
      );
    case DioExceptionType.badCertificate:
      return const ApiClientException(
        'The server certificate could not be trusted.',
      );
    case DioExceptionType.cancel:
      return const ApiClientException('The request was cancelled.');
    case DioExceptionType.unknown:
      return ApiClientException(
        error.message ?? 'The request failed before the server could respond.',
      );
  }
}

SyncApiErrorInfo inspectSyncApiError(Object error) {
  if (error is DioException) {
    final backendError = _extractBackendError(error);
    final code = backendError?['code']?.toString();
    final backendMessage = backendError?['message']?.toString();
    final statusCode = error.response?.statusCode;

    if (backendMessage != null && backendMessage.isNotEmpty) {
      return SyncApiErrorInfo(
        message: _friendlyBackendMessage(
          code: code,
          backendMessage: backendMessage,
        ),
        code: code,
        statusCode: statusCode,
      );
    }

    return SyncApiErrorInfo(
      message: _friendlyTransportMessage(error),
      code: code,
      statusCode: statusCode,
    );
  }

  final text = error.toString().trim();
  return SyncApiErrorInfo(
    message: text.isEmpty
        ? 'Something went wrong while talking to the backend.'
        : text,
  );
}

String formatSyncApiError(
  Object error, {
  String fallback = 'Something went wrong while talking to the backend.',
}) {
  final info = inspectSyncApiError(error);
  final message = info.message.trim();
  return message.isEmpty ? fallback : message;
}

Map<String, dynamic>? _extractBackendError(DioException error) {
  final data = error.response?.data;
  if (data is Map<String, dynamic>) {
    final nested = data['error'];
    if (nested is Map<String, dynamic>) {
      return nested;
    }
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
  }
  if (data is Map) {
    final normalized = Map<String, dynamic>.from(data);
    final nested = normalized['error'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
  }
  return null;
}

String _friendlyBackendMessage({
  required String? code,
  required String backendMessage,
}) {
  return switch (code) {
    'auth_invalid' =>
      'Add the backend auth token in Connection before retrying.',
    'asset_too_large' =>
      'One of the selected files is larger than this server currently allows. Pick a smaller file or raise the upload limit on your server.',
    'project_not_found' =>
      'The selected project could not be found on this backend. Pick another target or create a new import.',
    'reader_model_not_found' || 'sync_not_found' =>
      'This project exists, but its reading artifacts are not ready yet. Wait for alignment to finish and refresh.',
    'asset_not_ready' =>
      'The book or audio upload is not finished yet. Retry after the upload completes.',
    'asset_empty_upload' =>
      'One of the selected files was empty. Pick a valid EPUB or audio file.',
    'audio_processing_failed' =>
      'Sync could not read this audiobook file. Try a standard audiobook file such as MP3, M4B, M4A, OGG, WAV, or FLAC.',
    'epub_processing_failed' =>
      'The EPUB uploaded, but Sync could not turn it into a readable model. Try a cleaner EPUB file.',
    'asset_content_missing' =>
      'The backend knows about this file, but the stored content is missing. Re-upload the project assets.',
    'job_dispatch_failed' =>
      'The files uploaded, but the server could not start syncing yet. Try again in a moment.',
    _ => backendMessage,
  };
}

String _friendlyTransportMessage(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      'The app could not reach the backend. Check the server URL, network path, or Tailscale connection and try again.',
    DioExceptionType.badCertificate =>
      'The backend TLS certificate was rejected on this device.',
    DioExceptionType.badResponse => switch (error.response?.statusCode) {
      401 => 'This backend requires a valid auth token.',
      404 => 'The requested project or artifact was not found on the backend.',
      409 =>
        'The backend is not ready for this step yet. Wait for processing to finish and retry.',
      422 =>
        'The backend rejected the request data. Check the selected files and input fields.',
      500 || 502 || 503 || 504 =>
        'The backend is up, but it failed to complete the request. Retry in a moment.',
      _ =>
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'The backend returned an unexpected response.',
    },
    DioExceptionType.cancel =>
      'The request was cancelled before the backend finished responding.',
    DioExceptionType.unknown =>
      error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'The backend request failed for an unknown reason.',
  };
}
