import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/app.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
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

void main() {
  testWidgets('renders reader shell and playback controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readerRepositoryProvider.overrideWithValue(_FakeReaderRepository()),
          projectEventsProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const SyncApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Moby-Dick'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
  });
}
