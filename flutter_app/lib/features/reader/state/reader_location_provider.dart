import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';

final readerLocationStoreProvider = Provider<ReaderLocationStore>(
  (ref) => const FileReaderLocationStore(),
);

final readerLocationRevisionProvider =
    NotifierProvider<ReaderLocationRevisionController, int>(
      ReaderLocationRevisionController.new,
    );

class ReaderLocationRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state += 1;
  }
}

final recentReaderLocationsProvider =
    FutureProvider<List<ReaderLocationSnapshot>>((ref) async {
      ref.watch(readerLocationRevisionProvider);
      return ref.watch(readerLocationStoreProvider).loadRecent();
    });
