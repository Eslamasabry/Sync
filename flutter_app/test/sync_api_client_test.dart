import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';

void main() {
  test('fetchReaderModel follows download_url metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final readerModelPayload = {
      'book_id': 'demo-book',
      'title': 'Moby-Dick',
      'language': 'en',
      'sections': [
        {
          'id': 'section-1',
          'title': 'Loomings',
          'order': 0,
          'paragraphs': [
            {
              'index': 0,
              'tokens': [
                {
                  'index': 0,
                  'text': 'Call',
                  'normalized': 'call',
                  'cfi': '/6/2/4',
                },
              ],
            },
          ],
        },
      ],
    };

    server.listen((request) async {
      if (request.uri.path == '/v1/projects/demo-book/reader-model') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'project_id': 'demo-book',
              'download_url':
                  'http://${server.address.host}:${server.port}/downloads/reader-model.json',
            }),
          );
      } else if (request.uri.path == '/downloads/reader-model.json') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(readerModelPayload));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }

      await request.response.close();
    });

    final client = SyncApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
    );
    final readerModel = await client.fetchReaderModel('demo-book');

    expect(readerModel.bookId, 'demo-book');
    expect(readerModel.title, 'Moby-Dick');
    expect(readerModel.sections.single.title, 'Loomings');
  });

  test(
    'sync api client sends bearer auth to metadata and download routes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var metadataAuthorized = false;
      var downloadAuthorized = false;

      server.listen((request) async {
        final isAuthorized =
            request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer secret-token';
        if (request.uri.path == '/v1/projects/demo-book/reader-model') {
          metadataAuthorized = isAuthorized;
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'project_id': 'demo-book',
                'download_url':
                    'http://${server.address.host}:${server.port}/downloads/reader-model.json',
              }),
            );
        } else if (request.uri.path == '/downloads/reader-model.json') {
          downloadAuthorized = isAuthorized;
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'book_id': 'demo-book',
                'title': 'Moby-Dick',
                'language': 'en',
                'sections': const [],
              }),
            );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }

        await request.response.close();
      });

      final client = SyncApiClient(
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        authToken: 'secret-token',
      );
      await client.fetchReaderModel('demo-book');

      expect(metadataAuthorized, isTrue);
      expect(downloadAuthorized, isTrue);
      expect(client.authorizationHeaders, {
        'Authorization': 'Bearer secret-token',
      });
    },
  );

  test('sync api client creates projects and alignment jobs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    var createProjectBody = '';
    var createJobBody = '';

    server.listen((request) async {
      if (request.uri.path == '/v1/projects' && request.method == 'POST') {
        createProjectBody = await utf8.decoder.bind(request).join();
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'project_id': 'project-123',
              'status': 'created',
              'created_at': '2026-03-09T00:00:00Z',
            }),
          );
      } else if (request.uri.path == '/v1/projects/project-123/jobs' &&
          request.method == 'POST') {
        createJobBody = await utf8.decoder.bind(request).join();
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'job_id': 'job-123',
              'status': 'queued',
              'reused_existing': false,
              'attempt_number': 1,
              'retry_of_job_id': null,
            }),
          );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }

      await request.response.close();
    });

    final client = SyncApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
    );
    final project = await client.createProject(
      title: 'Imported Book',
      language: 'en',
    );
    final job = await client.createAlignmentJob(
      projectId: project.projectId,
      bookAssetId: 'book-asset-1',
      audioAssetIds: const ['audio-1', 'audio-2'],
    );

    expect(project.projectId, 'project-123');
    expect(job.jobId, 'job-123');
    expect(jsonDecode(createProjectBody), {
      'title': 'Imported Book',
      'language': 'en',
    });
    expect(jsonDecode(createJobBody), {
      'job_type': 'alignment',
      'book_asset_id': 'book-asset-1',
      'audio_asset_ids': ['audio-1', 'audio-2'],
    });
  });
}
