import 'package:dio/dio.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';

class SyncApiClient {
  SyncApiClient({Dio? dio, String baseUrl = 'http://localhost:8000/v1'})
    : _baseUrl = baseUrl,
      _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final String _baseUrl;
  final Dio _dio;

  Future<ReaderModel> fetchReaderModel(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/projects/$projectId/reader-model',
    );
    return ReaderModel.fromJson(
      response.data!['model'] as Map<String, dynamic>,
    );
  }

  Future<SyncArtifact> fetchSyncArtifact(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/projects/$projectId/sync',
    );
    final payload = response.data!['inline_payload'] as Map<String, dynamic>;
    return SyncArtifact.fromJson(payload);
  }

  String assetContentUrl({required String projectId, required String assetId}) {
    return '$_baseUrl/projects/$projectId/assets/$assetId/content';
  }
}
