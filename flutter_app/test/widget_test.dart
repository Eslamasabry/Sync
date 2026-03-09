import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sync_flutter/app.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';
import 'package:sync_flutter/features/reader/state/sample_reader_data.dart';

class _FakeReaderRepository extends ReaderRepository {
  _FakeReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    return ReaderProjectBundle(
      projectId: 'demo-book',
      readerModel: demoReaderModel,
      syncArtifact: demoSyncArtifact,
      source: ReaderContentSource.api,
      audioUrls: const [],
    );
  }
}

class _FrontMatterReaderRepository extends ReaderRepository {
  _FrontMatterReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    return ReaderProjectBundle(
      projectId: 'demo-book',
      readerModel: demoReaderModel,
      syncArtifact: SyncArtifact.fromJson({
        'version': '1.0',
        'book_id': 'demo-book',
        'language': 'en',
        'audio': [
          {'asset_id': 'audio-demo', 'offset_ms': 0, 'duration_ms': 3520},
        ],
        'content_start_ms': 1200,
        'content_end_ms': 3520,
        'tokens': [
          {
            'id': 0,
            'text': 'Call',
            'normalized': 'call',
            'start_ms': 1200,
            'end_ms': 1500,
            'confidence': 1.0,
            'location': {
              'section_id': 's1',
              'paragraph_index': 0,
              'token_index': 0,
              'cfi': '/6/2/4',
            },
          },
        ],
        'gaps': [
          {
            'start_ms': 0,
            'end_ms': 1200,
            'reason': 'audiobook_front_matter',
            'transcript_start_index': 0,
            'transcript_end_index': 4,
            'word_count': 5,
          },
        ],
      }),
      source: ReaderContentSource.api,
      audioUrls: const [],
    );
  }
}

class _FailingReaderRepository extends ReaderRepository {
  _FailingReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/projects/$projectId/reader-model'),
      message:
          'Reader model response did not include an inline model or download URL.',
      type: DioExceptionType.badResponse,
    );
  }
}

Future<void> _pumpReaderApp(
  WidgetTester tester, {
  required ReaderRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        readerRepositoryProvider.overrideWithValue(repository),
        projectEventsProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: const SyncApp(),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders reader shell and playback controls', (tester) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Moby-Dick'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
  });

  testWidgets('shows start book affordance when sync has front matter', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FrontMatterReaderRepository());

    expect(find.text('Start Book'), findsOneWidget);
    expect(
      find.textContaining('Intro detected before the book starts'),
      findsOneWidget,
    );
  });

  testWidgets('start book action skips the intro banner', (tester) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    expect(find.text('Start Book'), findsOneWidget);

    await tester.tap(find.text('Start Book'));
    await tester.pump();

    expect(find.text('Start Book'), findsNothing);
    expect(
      find.textContaining('Intro detected before the book starts'),
      findsNothing,
    );
  });

  testWidgets('shows unmatched narration messaging for a mid-book gap', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1800);
    await tester.pump();

    expect(
      find.text('Playback is in an unmatched narration span.'),
      findsOneWidget,
    );
  });

  testWidgets('shows audiobook outro messaging near the end matter window', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(4500);
    await tester.pump();

    expect(
      find.text(
        'This portion is audiobook outro and is outside the EPUB text.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows the reader error state when a real project load fails', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FailingReaderRepository());
    await tester.pumpAndSettle();

    expect(find.text('Reader failed to load'), findsOneWidget);
    expect(find.textContaining('Reader model response'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
