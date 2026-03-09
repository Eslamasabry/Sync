import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sync_flutter/app.dart';
import 'package:sync_flutter/core/playback/playback_driver.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';
import 'package:sync_flutter/features/reader/state/sample_reader_data.dart';

class _FakePlaybackDriver implements PlaybackDriver {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _playingController.close();
  }

  @override
  Future<void> pause() async {
    _playingController.add(false);
  }

  @override
  Future<void> play() async {
    _playingController.add(true);
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setUrls(List<String> urls) async {
    _playingController.add(false);
    _positionController.add(Duration.zero);
  }
}

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
      totalAudioAssets: demoSyncArtifact.audio.length,
      cachedAudioAssets: 0,
      hasCompleteOfflineAudio: false,
      statusMessage:
          'Synced text is available, but no playable audio asset was returned by the backend.',
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
      totalAudioAssets: 1,
      cachedAudioAssets: 0,
      hasCompleteOfflineAudio: false,
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

class _PendingReaderRepository extends ReaderRepository {
  _PendingReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    return ReaderProjectBundle(
      projectId: 'pending-book',
      readerModel: ReaderModel(
        bookId: 'pending-book',
        title: 'Pending Project',
        language: 'en',
        sections: const [],
      ),
      syncArtifact: SyncArtifact(
        version: '1.0',
        bookId: 'pending-book',
        language: 'en',
        audio: const [],
        contentStartMs: 0,
        contentEndMs: 0,
        tokens: const [],
        gaps: const [],
      ),
      source: ReaderContentSource.artifactPending,
      audioUrls: const [],
      totalAudioAssets: 0,
      cachedAudioAssets: 0,
      hasCompleteOfflineAudio: false,
      statusMessage:
          'Pending Project is still processing. Keep this screen open or refresh after alignment completes.',
    );
  }
}

class _CachedReaderRepository extends ReaderRepository {
  _CachedReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    return ReaderProjectBundle(
      projectId: 'cached-book',
      readerModel: demoReaderModel,
      syncArtifact: demoSyncArtifact,
      source: ReaderContentSource.offlineCache,
      audioUrls: const [],
      totalAudioAssets: 1,
      cachedAudioAssets: 0,
      hasCompleteOfflineAudio: false,
      statusMessage:
          'Cached reader artifacts loaded from this device. Audio streaming stays disabled until the backend is reachable again. Cached at 2026-03-09T12:00:00.',
      cachedAt: DateTime.utc(2026, 3, 9, 12),
    );
  }
}

class _StreamingAudioReaderRepository extends ReaderRepository {
  _StreamingAudioReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    return ReaderProjectBundle(
      projectId: 'streaming-book',
      readerModel: demoReaderModel,
      syncArtifact: demoSyncArtifact,
      source: ReaderContentSource.api,
      audioUrls: const ['https://example.com/audio-demo.mp3'],
      totalAudioAssets: 1,
      cachedAudioAssets: 0,
      hasCompleteOfflineAudio: false,
      statusMessage:
          'Audio will stream from the backend until you download it.',
    );
  }
}

class _MixedAudioReaderRepository extends ReaderRepository {
  _MixedAudioReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    return ReaderProjectBundle(
      projectId: 'mixed-book',
      readerModel: demoReaderModel,
      syncArtifact: SyncArtifact.fromJson({
        'version': '1.0',
        'book_id': 'mixed-book',
        'language': 'en',
        'audio': [
          {'asset_id': 'audio-local', 'offset_ms': 0, 'duration_ms': 4700},
          {'asset_id': 'audio-remote', 'offset_ms': 4700, 'duration_ms': 4200},
        ],
        'content_start_ms': 600,
        'content_end_ms': 4300,
        'tokens': demoSyncArtifact.toJson()['tokens'],
        'gaps': demoSyncArtifact.toJson()['gaps'],
      }),
      source: ReaderContentSource.api,
      audioUrls: const [
        'file:///tmp/audio-local.mp3',
        'https://example.com/audio-remote.mp3',
      ],
      totalAudioAssets: 2,
      cachedAudioAssets: 1,
      hasCompleteOfflineAudio: false,
      audioCachedAt: DateTime.utc(2026, 3, 9, 12),
      statusMessage: '1 of 2 audio files are downloaded locally.',
    );
  }
}

class _OfflineAudioReaderRepository extends ReaderRepository {
  _OfflineAudioReaderRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  @override
  Future<ReaderProjectBundle> loadProject(String projectId) async {
    return ReaderProjectBundle(
      projectId: 'offline-book',
      readerModel: demoReaderModel,
      syncArtifact: demoSyncArtifact,
      source: ReaderContentSource.offlineCache,
      audioUrls: const ['file:///tmp/audio-demo.mp3'],
      totalAudioAssets: 1,
      cachedAudioAssets: 1,
      hasCompleteOfflineAudio: true,
      cachedAt: DateTime.utc(2026, 3, 9, 12),
      audioCachedAt: DateTime.utc(2026, 3, 9, 12),
      statusMessage:
          'Cached reader artifacts and downloaded audio loaded from this device.',
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
        playbackDriverProvider.overrideWithValue(_FakePlaybackDriver()),
      ],
      child: const SyncApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders reader shell and playback controls', (tester) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Moby-Dick'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Download Audio'), findsOneWidget);
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

    await tester.ensureVisible(find.text('Start Book'));
    await tester.pumpAndSettle();
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

  testWidgets(
    'shows the repository status banner for incomplete backend audio',
    (tester) async {
      await _pumpReaderApp(tester, repository: _FakeReaderRepository());

      expect(
        find.textContaining('no playable audio asset was returned'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows a backend pending state instead of demo fallback', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _PendingReaderRepository());
    await tester.pumpAndSettle();

    expect(find.textContaining('still processing'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('there is no normalized reader model to render yet'),
      findsOneWidget,
    );
    expect(
      find.text('Demo data loaded because the API is unavailable.'),
      findsNothing,
    );
  });

  testWidgets('shows cached offline source messaging distinctly', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _CachedReaderRepository());
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Cached reader artifacts loaded from this device'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Audio streaming stays disabled until the backend is reachable again',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Demo data loaded because the API is unavailable.'),
      findsNothing,
    );
    expect(find.text('Download Audio'), findsOneWidget);
  });

  testWidgets('shows text-only diagnostics when audio is not playable', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    expect(find.text('Playback source: text timeline only.'), findsOneWidget);
    expect(find.text('Text timeline mode'), findsOneWidget);
    expect(
      find.textContaining('no playable local or remote source is active'),
      findsOneWidget,
    );
  });

  testWidgets('shows streaming-only diagnostics for backend audio', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _StreamingAudioReaderRepository());
    await tester.pumpAndSettle();

    expect(
      find.text('Playback source: streaming from the backend.'),
      findsOneWidget,
    );
    expect(find.text('Local audio 0/1'), findsOneWidget);
    expect(find.text('Streaming 1'), findsOneWidget);
    expect(find.text('Native audio active'), findsOneWidget);
    expect(find.text('Download Audio'), findsOneWidget);
  });

  testWidgets('shows mixed local and streaming diagnostics', (tester) async {
    await _pumpReaderApp(tester, repository: _MixedAudioReaderRepository());
    await tester.pumpAndSettle();

    expect(
      find.text('Playback source: mixed local and backend audio.'),
      findsOneWidget,
    );
    expect(find.text('Local audio 1/2'), findsOneWidget);
    expect(find.text('Streaming 1'), findsOneWidget);
    expect(
      find.textContaining('The rest will stream from the backend'),
      findsOneWidget,
    );
    expect(find.text('Download Remaining'), findsOneWidget);
    expect(find.textContaining('Audio cache 2026-03-09 16:00'), findsOneWidget);
  });

  testWidgets('shows full offline audio diagnostics distinctly', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _OfflineAudioReaderRepository());
    await tester.pumpAndSettle();

    expect(find.text('Playback source: local cached audio.'), findsOneWidget);
    expect(find.text('Local audio 1/1'), findsOneWidget);
    expect(find.text('Native audio active'), findsOneWidget);
    expect(
      find.textContaining('All project audio is downloaded on this device'),
      findsOneWidget,
    );
    expect(find.text('Remove Local Copy'), findsOneWidget);
    expect(find.text('Streaming 1'), findsNothing);
  });
}
