import 'package:dio/dio.dart';
import 'package:sync_flutter/core/import/import_file_picker.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';

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
  }

  Future<SyncArtifact> fetchSyncArtifact(String projectId) async {
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
  }

  Future<Map<String, dynamic>> fetchProjectDetail(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/projects/$projectId',
    );
    return _asMap(response.data, context: 'project detail response');
  }

  Future<ProjectCreateResult> createProject({
    required String title,
    required String language,
  }) async {
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
      throw ArgumentError('Import file must include a path or in-memory bytes.');
    }

    final formData = FormData.fromMap({'kind': kind, 'file': multipartFile});
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
  }

  Future<AlignmentJobResult> createAlignmentJob({
    required String projectId,
    required String bookAssetId,
    required List<String> audioAssetIds,
  }) async {
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
  }

  Future<AlignmentJobResult> fetchJob({
    required String projectId,
    required String jobId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/projects/$projectId/jobs/$jobId',
    );
    return _parseJobResult(_asMap(response.data, context: 'job detail response'));
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
