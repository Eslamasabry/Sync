import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeTabProvider = NotifierProvider<HomeTabController, int>(
  HomeTabController.new,
);

enum HomeTabDestination { library, reader }

class HomeTabController extends Notifier<int> {
  bool _hasPinnedSelection = false;

  @override
  int build() => HomeTabDestination.library.index;

  void syncEntryPreference({required bool hasReaderTarget}) {
    if (_hasPinnedSelection) {
      if (!hasReaderTarget && state == HomeTabDestination.reader.index) {
        _hasPinnedSelection = false;
        state = HomeTabDestination.library.index;
      }
      return;
    }

    final preferred = hasReaderTarget
        ? HomeTabDestination.reader.index
        : HomeTabDestination.library.index;
    if (state != preferred) {
      state = preferred;
    }
  }

  void showLibrary() {
    _hasPinnedSelection = true;
    if (state != HomeTabDestination.library.index) {
      state = HomeTabDestination.library.index;
    }
  }

  void showReader() {
    _hasPinnedSelection = true;
    if (state != HomeTabDestination.reader.index) {
      state = HomeTabDestination.reader.index;
    }
  }

  void useAutomaticEntryPreference() {
    _hasPinnedSelection = false;
  }
}
