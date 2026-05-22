import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/auth/data/xboard_api_client.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

/// Auth state: idle | loading | authenticated | error
enum AuthStatus { idle, loading, authenticated, error }

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthStatus>(() => AuthNotifier());

class AuthNotifier extends AsyncNotifier<AuthStatus> with AppLogger {
  @override
  Future<AuthStatus> build() async {
    final panelUrl = _readPanelUrl();
    final sanctumToken = _readSanctumToken();
    final email = _readEmail();

    if (panelUrl != null &&
        sanctumToken != null &&
        sanctumToken.isNotEmpty &&
        email != null &&
        email.isNotEmpty) {
      loggy.debug('Auth: found stored credentials for $email');
      return AuthStatus.authenticated;
    }
    return AuthStatus.idle;
  }

  String? _readPanelUrl() =>
      ref.read(sharedPreferencesProvider).requireValue.getString('auth_panel_url');

  String? _readSanctumToken() =>
      ref.read(sharedPreferencesProvider).requireValue.getString('auth_sanctum_token');

  String? _readSubscriptionToken() =>
      ref.read(sharedPreferencesProvider).requireValue.getString('auth_subscription_token');

  String? _readSubscribeUrl() =>
      ref.read(sharedPreferencesProvider).requireValue.getString('auth_subscribe_url');

  String? _readEmail() =>
      ref.read(sharedPreferencesProvider).requireValue.getString('auth_email');

  String? get panelUrl => _readPanelUrl();
  String? get email => _readEmail();
  String? get sanctumToken => _readSanctumToken();
  String? get subscriptionToken => _readSubscriptionToken();

  Future<void> _writePreference(String key, String value) async {
    await ref
        .read(sharedPreferencesProvider)
        .requireValue
        .setString(key, value);
  }

  Future<void> _removePreference(String key) async {
    await ref
        .read(sharedPreferencesProvider)
        .requireValue
        .remove(key);
  }

  /// Login to Xboard panel
  Future<void> login({
    required String panelUrl,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final normalizedUrl = panelUrl.replaceAll(RegExp(r'/+$'), '');
      final client = XboardApiClient(baseUrl: normalizedUrl);

      // Step 1: Login
      loggy.debug('Auth: logging in to $normalizedUrl as $email');
      final loginResult = await client.login(email: email, password: password);

      // Step 2: Get subscription info (includes subscribe_url)
      client.setToken(loginResult.sanctumToken);
      final subscribeResult = await client.getSubscribe();

      // Step 3: Persist credentials
      await _writePreference('auth_panel_url', normalizedUrl);
      await _writePreference('auth_sanctum_token', loginResult.sanctumToken);
      await _writePreference(
        'auth_subscription_token',
        loginResult.subscriptionToken,
      );
      // Save the full subscribe URL from API (more reliable than constructing manually)
      if (subscribeResult.subscribeUrl.isNotEmpty) {
        await _writePreference('auth_subscribe_url', subscribeResult.subscribeUrl);
      }
      await _writePreference('auth_email', email);

      loggy.debug('Auth: login successful for $email');
      return AuthStatus.authenticated;
    });
  }

  /// Build the full subscribe URL from stored credentials
  String? get subscribeUrl {
    // Priority 1: use the subscribe_url returned by the API
    final savedUrl = _readSubscribeUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) return savedUrl;

    // Priority 2: fall back to constructing from panel URL + token
    final panelUrl = _readPanelUrl();
    final token = _readSubscriptionToken();
    if (panelUrl == null || token == null) return null;
    return '$panelUrl/s/$token';
  }

  /// Logout: clear all credentials and configs
  Future<void> logout() async {
    await _removePreference('auth_panel_url');
    await _removePreference('auth_sanctum_token');
    await _removePreference('auth_subscription_token');
    await _removePreference('auth_subscribe_url');
    await _removePreference('auth_email');

    // Delete all config files and database entries
    try {
      final dirs = ref.read(appDirectoriesProvider).requireValue;
      final configsDir = Directory(p.join(dirs.workingDir.path, 'configs'));
      if (await configsDir.exists()) {
        await configsDir.delete(recursive: true);
      }

      final db = ref.read(dbProvider);
      await db.delete(db.profileEntries).go();
      await db.delete(db.appProxyEntries).go();
    } catch (e, st) {
      loggy.warning('Failed to clean up profile data on logout', e, st);
    }

    state = const AsyncData(AuthStatus.idle);
    loggy.debug('Auth: logged out, credentials and configs cleared');
  }
}
