import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sync_flutter/app.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage_types.dart';
import 'package:sync_flutter/core/playback/playback_driver.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_location_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';
import 'package:sync_flutter/features/reader/state/sample_reader_data.dart';
import 'package:sync_flutter/features/reader/state/reader_study_provider.dart';
import 'package:sync_flutter/features/reader/data/reader_study_store.dart';

class _FakePlaybackDriver implements PlaybackDriver {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  Duration? lastSeek;
  double? lastSpeed;
  List<String> urls = const [];

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
    lastSeek = position;
    _positionController.add(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> setUrls(List<String> urls) async {
    this.urls = List<String>.from(urls);
    _playingController.add(false);
    _positionController.add(Duration.zero);
  }
}

class _MemoryRuntimeConnectionSettingsStorage
    implements RuntimeConnectionSettingsStorage {
  _MemoryRuntimeConnectionSettingsStorage({
    List<RuntimeConnectionSettings>? recent,
  }) : _recent = [...?recent];

  RuntimeConnectionSettings? _settings = defaultConnectionSettings;
  final List<RuntimeConnectionSettings> _recent;

  @override
  Future<void> clear() async {
    _settings = null;
    _recent.clear();
  }

  @override
  Future<RuntimeConnectionSettings?> load() async => _settings;

  @override
  Future<List<RuntimeConnectionSettings>> loadRecent() async => [..._recent];

  @override
  Future<void> store(RuntimeConnectionSettings settings) async {
    _settings = settings;
    _recent
      ..removeWhere((item) => item.identityKey == settings.identityKey)
      ..insert(0, settings);
  }
}

class _MemoryReaderLocationStore implements ReaderLocationStore {
  _MemoryReaderLocationStore({Map<String, ReaderLocationSnapshot>? initial})
    : _items = {...?initial};

  final Map<String, ReaderLocationSnapshot> _items;

  @override
  Future<ReaderLocationSnapshot?> loadProject(String projectId) async =>
      _items[projectId];

  @override
  Future<List<ReaderLocationSnapshot>> loadRecent() async {
    final values = _items.values.toList(growable: false);
    values.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return values;
  }

  @override
  Future<void> removeProject(String projectId) async {
    _items.remove(projectId);
  }

  @override
  Future<void> storeProject(ReaderLocationSnapshot snapshot) async {
    _items[snapshot.projectId] = snapshot;
  }
}

class _MemoryReaderStudyStore implements ReaderStudyStore {
  _MemoryReaderStudyStore({Map<String, List<ReaderStudyEntry>>? initial})
    : _items = {...?initial};

  final Map<String, List<ReaderStudyEntry>> _items;

  @override
  Future<List<ReaderStudyEntry>> loadProject(String projectId) async => [
    ...?_items[projectId],
  ];

  @override
  Future<void> saveProject(
    String projectId,
    List<ReaderStudyEntry> entries,
  ) async {
    _items[projectId] = [...entries];
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

Future<ProviderContainer> _pumpReaderApp(
  WidgetTester tester, {
  required ReaderRepository repository,
  _MemoryRuntimeConnectionSettingsStorage? settingsStorage,
  ReaderLocationStore? locationStore,
  ReaderStudyStore? studyStore,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1440, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      runtimeConnectionSettingsStorageProvider.overrideWithValue(
        settingsStorage ?? _MemoryRuntimeConnectionSettingsStorage(),
      ),
      readerLocationStoreProvider.overrideWithValue(
        locationStore ?? _MemoryReaderLocationStore(),
      ),
      readerStudyStoreProvider.overrideWithValue(
        studyStore ?? _MemoryReaderStudyStore(),
      ),
      readerRepositoryProvider.overrideWith((ref) async => repository),
      projectEventsProvider.overrideWith((ref) => const Stream.empty()),
      playbackDriverProvider.overrideWithValue(_FakePlaybackDriver()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SyncApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

ProviderContainer _playbackContainer({
  _FakePlaybackDriver? driver,
  ReaderLocationStore? locationStore,
}) {
  final fakeDriver = driver ?? _FakePlaybackDriver();
  return ProviderContainer(
    overrides: [
      readerLocationStoreProvider.overrideWithValue(
        locationStore ?? _MemoryReaderLocationStore(),
      ),
      playbackDriverProvider.overrideWithValue(fakeDriver),
    ],
  );
}

ReaderProjectBundle _playbackBundle({
  SyncArtifact? syncArtifact,
  List<String> audioUrls = const [],
}) {
  final artifact = syncArtifact ?? demoSyncArtifact;
  return ReaderProjectBundle(
    projectId: artifact.bookId,
    readerModel: demoReaderModel,
    syncArtifact: artifact,
    source: ReaderContentSource.api,
    audioUrls: audioUrls,
    totalAudioAssets: artifact.audio.length,
    cachedAudioAssets: 0,
    hasCompleteOfflineAudio: false,
  );
}

SyncArtifact _extendedSyncArtifact() {
  return SyncArtifact.fromJson({
    'version': '1.0',
    'book_id': 'timeline-book',
    'language': 'en',
    'audio': [
      {'asset_id': 'audio-demo', 'offset_ms': 0, 'duration_ms': 32000},
    ],
    'content_start_ms': 1000,
    'content_end_ms': 30000,
    'tokens': [
      for (var index = 0; index < 10; index += 1)
        {
          'id': index,
          'text': 'word$index',
          'normalized': 'word$index',
          'start_ms': 1000 + (index * 3000),
          'end_ms': 1800 + (index * 3000),
          'confidence': 1.0,
          'location': {
            'section_id': 's1',
            'paragraph_index': 0,
            'token_index': index,
            'cfi': '/6/2/${4 + index}',
          },
        },
    ],
    'gaps': const [],
  });
}

void main() {
  test(
    'controller starts native playback from loop A when outside the loop',
    () async {
      final driver = _FakePlaybackDriver();
      final container = _playbackContainer(driver: driver);
      addTearDown(container.dispose);

      final controller = container.read(readerPlaybackProvider.notifier);
      await controller.configureProject(
        _playbackBundle(audioUrls: const ['file:///tmp/audio-demo.mp3']),
      );
      await controller.seekTo(1200);
      controller.markLoopStart();
      await controller.seekTo(2500);
      controller.markLoopEnd();
      await controller.seekTo(4100);

      await controller.togglePlayback(demoSyncArtifact.totalDurationMs);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(readerPlaybackProvider);
      expect(state.isPlaying, isTrue);
      expect(state.positionMs, 1200);
      expect(driver.lastSeek, const Duration(milliseconds: 1200));
    },
  );

  test(
    'controller uses sync-aware skip anchors and respects loop boundaries',
    () async {
      final container = _playbackContainer();
      addTearDown(container.dispose);

      final controller = container.read(readerPlaybackProvider.notifier);
      await controller.configureProject(
        _playbackBundle(syncArtifact: _extendedSyncArtifact()),
      );
      await controller.seekTo(14000);

      controller.forward15Seconds();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(readerPlaybackProvider).positionMs, 28000);

      await controller.seekTo(22000);
      controller.markLoopStart();
      await controller.seekTo(26000);
      controller.markLoopEnd();
      await controller.seekTo(24000);

      controller.forward15Seconds();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(readerPlaybackProvider).positionMs, 26000);

      controller.rewind15Seconds();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(readerPlaybackProvider).positionMs, 22000);
    },
  );

  test('controller presets tune playback speed and focus defaults', () async {
    final driver = _FakePlaybackDriver();
    final container = _playbackContainer(driver: driver);
    addTearDown(container.dispose);

    final controller = container.read(readerPlaybackProvider.notifier);
    await controller.configureProject(
      _playbackBundle(audioUrls: const ['file:///tmp/audio-demo.mp3']),
    );

    await controller.applyPreset(ReaderPlaybackPreset.bedtime);
    var state = container.read(readerPlaybackProvider);
    expect(state.playbackPreset, ReaderPlaybackPreset.bedtime);
    expect(state.distractionFreeMode, isTrue);
    expect(state.followPlayback, isFalse);
    expect(state.speed, 0.85);
    expect(driver.lastSpeed, 0.85);

    await controller.applyPreset(ReaderPlaybackPreset.study);
    state = container.read(readerPlaybackProvider);
    expect(state.playbackPreset, ReaderPlaybackPreset.study);
    expect(state.distractionFreeMode, isFalse);
    expect(state.followPlayback, isTrue);
    expect(state.speed, 0.9);
    expect(driver.lastSpeed, 0.9);
  });

  testWidgets('renders reader shell and playback controls', (tester) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    expect(find.text('Sync'), findsAtLeastNWidgets(1));
    expect(find.text('Moby-Dick'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Download Audio'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
  });

  testWidgets('focus mode hides the hero and shows the floating reader HUD', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    expect(find.text('Connection'), findsNothing);
    expect(find.text('Exit Focus'), findsOneWidget);
  });

  testWidgets('reader exposes accessible section and paragraph landmarks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    expect(find.bySemanticsLabel(RegExp(r'Section Loomings')), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp(r'Paragraph 1\..*Call me Ishmael')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('enhanced contrast changes token emphasis styling', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    final beforeContainer = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('Call').first,
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final beforeDecoration = beforeContainer.decoration! as BoxDecoration;

    await tester.ensureVisible(find.text('Enhanced contrast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enhanced contrast'));
    await tester.pumpAndSettle();

    final afterContainer = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('Call').first,
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final afterDecoration = afterContainer.decoration! as BoxDecoration;

    expect(afterDecoration.color, isNot(equals(beforeDecoration.color)));
  });

  testWidgets('left-handed HUD moves the focus overlay to the lower left', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    await tester.ensureVisible(find.text('Left-handed HUD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left-handed HUD'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    final positioned = tester.widgetList<Positioned>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Positioned &&
            widget.bottom == 16 &&
            (widget.left == 16 || widget.right == 16),
      ),
    );

    expect(
      positioned.any((widget) => widget.left == 16 && widget.right == null),
      isTrue,
    );
  });

  testWidgets('text size controls change rendered token size', (tester) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    final before = tester.widget<Text>(find.text('Call').first);
    final beforeSize = before.style?.fontSize ?? 0;

    await tester.ensureVisible(find.text('Large').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large').first);
    await tester.pumpAndSettle();

    final after = tester.widget<Text>(find.text('Call').first);
    final afterSize = after.style?.fontSize ?? 0;

    expect(afterSize, greaterThan(beforeSize));
  });

  testWidgets('navigation sheet shows contents and text search results', (
    tester,
  ) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    await tester.tap(find.text('Navigate'));
    await tester.pumpAndSettle();

    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Loomings'), findsAtLeastNWidgets(1));

    await tester.enterText(find.byType(TextField), 'Ishmael');
    await tester.pumpAndSettle();

    expect(find.text('Search Results'), findsOneWidget);
    expect(find.textContaining('Call me Ishmael'), findsOneWidget);
  });

  testWidgets('saves runtime connection settings locally through the UI', (
    tester,
  ) async {
    final settingsStorage = _MemoryRuntimeConnectionSettingsStorage();
    await _pumpReaderApp(
      tester,
      repository: _FakeReaderRepository(),
      settingsStorage: settingsStorage,
    );

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'https://sync.example.ts.net/v1',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'private-book');
    await tester.enterText(find.byType(TextFormField).at(2), 'secret-token');
    await tester.tap(find.text('Save and Reload'));
    await tester.pumpAndSettle();

    expect(find.text('Project private-book'), findsOneWidget);
    expect(find.text('Server sync.example.ts.net'), findsOneWidget);
    expect(find.text('Auth enabled'), findsOneWidget);
  });

  testWidgets('shows recent connections and localhost guidance', (
    tester,
  ) async {
    final settingsStorage = _MemoryRuntimeConnectionSettingsStorage(
      recent: const [
        RuntimeConnectionSettings(
          apiBaseUrl: 'http://100.64.0.2:8000/v1',
          projectId: 'tailscale-book',
          authToken: 'token',
        ),
        RuntimeConnectionSettings(
          apiBaseUrl: 'http://localhost:8000/v1',
          projectId: 'local-book',
          authToken: '',
        ),
      ],
    );

    await _pumpReaderApp(
      tester,
      repository: _FakeReaderRepository(),
      settingsStorage: settingsStorage,
    );

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    expect(find.text('Recent Connections'), findsOneWidget);
    expect(find.text('100.64.0.2:8000 • tailscale-book'), findsOneWidget);
    expect(find.text('localhost:8000 • local-book'), findsOneWidget);
    expect(
      find.textContaining('localhost points to the phone itself'),
      findsOneWidget,
    );
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

  testWidgets('restores persisted reading location on reload', (tester) async {
    final container = await _pumpReaderApp(
      tester,
      repository: _FakeReaderRepository(),
      locationStore: _MemoryReaderLocationStore(
        initial: {
          'demo-book': ReaderLocationSnapshot(
            projectId: 'demo-book',
            positionMs: 2600,
            totalDurationMs: demoSyncArtifact.totalDurationMs,
            contentStartMs: demoSyncArtifact.contentStartMs,
            contentEndMs: demoSyncArtifact.contentEndMs,
            progressFraction: 0.54,
            sectionId: 's1',
            sectionTitle: 'Loomings',
            updatedAt: DateTime.utc(2026, 3, 9, 12),
          ),
        },
      ),
    );

    final playback = container.read(readerPlaybackProvider);
    expect(playback.positionMs, 2600);
    expect(find.textContaining('Book 54% complete'), findsOneWidget);
  });

  testWidgets('opens the sync inspector and lists gap spans', (tester) async {
    await _pumpReaderApp(tester, repository: _FakeReaderRepository());

    await tester.tap(find.byIcon(Icons.radar_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Sync Inspector'), findsOneWidget);
    expect(find.text('Audiobook intro'), findsAtLeastNWidgets(1));
    expect(find.text('Audiobook outro'), findsAtLeastNWidgets(1));
  });

  testWidgets('saves bookmarks and shows them in the review tray', (
    tester,
  ) async {
    final studyStore = _MemoryReaderStudyStore();
    await _pumpReaderApp(
      tester,
      repository: _FakeReaderRepository(),
      studyStore: studyStore,
    );

    await tester.ensureVisible(find.text('Save Bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Bookmark'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review Tray'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review Tray'));
    await tester.pumpAndSettle();

    expect(find.text('Review Tray'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Bookmark • 00:00'), findsOneWidget);
    expect(find.textContaining('Bookmark • 00:00\nMoby-Dick'), findsOneWidget);
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
