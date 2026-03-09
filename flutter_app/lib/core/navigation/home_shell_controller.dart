import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeTabProvider = NotifierProvider<HomeTabController, int>(
  HomeTabController.new,
);

class HomeTabController extends Notifier<int> {
  @override
  int build() => 1;

  void showLibrary() {
    state = 0;
  }

  void showReader() {
    state = 1;
  }
}
