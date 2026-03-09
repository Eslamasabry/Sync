import 'package:dio/dio.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';

class SyncApiClient {
  SyncApiClient({Dio? dio, String baseUrl = 'http://localhost:8000/v1'})
    : _baseUrl = _normalizeBaseUrl(baseUrl),
      _dio = dio ?? Dio(BaseOptions(baseUrl: _normalizeBaseUrl(baseUrl)));

  final String _baseUrl;
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
