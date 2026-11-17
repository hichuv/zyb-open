import 'package:flutter/foundation.dart';

final loginStateVersion = ValueNotifier<int>(0);
final rootTabIndex = ValueNotifier<int>(0);

void notifyLoginStateChanged() {
  loginStateVersion.value++;
}

void switchRootTab(int index) {
  rootTabIndex.value = index;
}
