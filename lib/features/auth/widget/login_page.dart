import 'package:flutter/material.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with AppLogger {
  final _formKey = GlobalKey<FormState>();
  final _panelUrlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isCreatingProfile = false;

  @override
  void dispose() {
    _panelUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authNotifierProvider.notifier).login(
      panelUrl: _panelUrlController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  Future<void> _createSubscriptionAndNavigate() async {
    if (_isCreatingProfile) return;
    _isCreatingProfile = true;

    try {
      final subscribeUrl = ref.read(authNotifierProvider.notifier).subscribeUrl;
      loggy.debug('Auto-subscribe: subscribeUrl=$subscribeUrl');

      if (subscribeUrl == null || subscribeUrl.isEmpty) {
        loggy.warning('Auto-subscribe: no subscribe URL available');
        ref.read(inAppNotificationControllerProvider).showErrorToast(
          '未获取到订阅地址，请稍后手动添加',
        );
        return;
      }

      final repo = await ref.read(profileRepositoryProvider.future);

      loggy.debug('Auto-subscribe: calling upsertRemote with URL');
      final result = await repo.upsertRemote(subscribeUrl).run();

      result.match(
        (failure) {
          loggy.warning('Auto-subscribe failed', failure);
          ref.read(inAppNotificationControllerProvider).showErrorToast(
            '订阅失败: ${failure.toString()}',
          );
        },
        (_) {
          loggy.info('Auto-subscribe succeeded');
          ref.read(inAppNotificationControllerProvider).showSuccessToast(
            '订阅成功',
          );
        },
      );
    } catch (e, st) {
      loggy.error('Auto-subscribe exception', e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(
        '订阅异常: ${e.toString()}',
      );
    } finally {
      _isCreatingProfile = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final theme = Theme.of(context);

    // After successful login, create subscription and navigate
    ref.listen(authNotifierProvider, (previous, next) {
      next.whenData((status) {
        if (status == AuthStatus.authenticated && previous?.valueOrNull != AuthStatus.authenticated) {
          _createSubscriptionAndNavigate();
        }
      });
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.vpn_lock_rounded,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'kuaifei',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '请登录您的账号',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Panel URL
                  TextFormField(
                    controller: _panelUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '面板地址',
                      hintText: 'https://your-panel.com',
                      prefixIcon: Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入面板地址';
                      }
                      final url = value.trim();
                      if (!url.startsWith('http://') && !url.startsWith('https://')) {
                        return '面板地址需以 http:// 或 https:// 开头';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Email
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      hintText: 'your@email.com',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入邮箱';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 24),

                  // Login button
                  FilledButton(
                    onPressed: authState.isLoading ? null : _handleLogin,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: authState.isLoading || _isCreatingProfile
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('登录', style: TextStyle(fontSize: 16)),
                  ),

                  // Error message
                  if (authState.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        authState.error.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
