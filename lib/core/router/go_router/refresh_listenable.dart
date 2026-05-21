import 'package:flutter/material.dart';
import 'package:hiddify/core/router/deep_linking/my_app_links.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// For temporary storage of the link received from AppLinks.
String newUrlFromAppLink = '';

class RefreshListenable extends ChangeNotifier {
  RefreshListenable(this.ref) {
    ref.listen(myAppLinksProvider, (_, next) {
      if (next.value != null) {
        newUrlFromAppLink = next.value!;
        notifyListeners();
      }
    });
    // Re-evaluate router redirects when auth state changes
    // (e.g., on app restart when stored credentials are found)
    ref.listen(authNotifierProvider, (_, __) {
      notifyListeners();
    });
  }
  final Ref ref;
}
