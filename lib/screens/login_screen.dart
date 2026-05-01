// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_colors.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _storage  = const FlutterSecureStorage();

  bool _loading  = false;
  bool _obscure  = true;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final remember = await _storage.read(key: 'driver_remember_me');
    if (remember == 'true') {
      final username = await _storage.read(key: 'driver_saved_username');
      final password = await _storage.read(key: 'driver_saved_password');
      if (username != null && password != null) {
        setState(() {
          _userCtrl.text = username;
          _passCtrl.text = password;
          _remember      = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      setState(() => _error = 'يرجى إدخال اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      // Save or clear credentials based on remember-me choice
      if (_remember) {
        await _storage.write(key: 'driver_remember_me',     value: 'true');
        await _storage.write(key: 'driver_saved_username',  value: _userCtrl.text.trim());
        await _storage.write(key: 'driver_saved_password',  value: _passCtrl.text.trim());
      } else {
        await _storage.delete(key: 'driver_remember_me');
        await _storage.delete(key: 'driver_saved_username');
        await _storage.delete(key: 'driver_saved_password');
      }

      // Clear any old tokens before login (member token or stale driver token)
      await _storage.delete(key: 'driver_token');

      final result = await ApiService.instance.login(
        _userCtrl.text.trim(),
        _passCtrl.text.trim(),
      );

      // Verify token was stored correctly
      final storedToken = await _storage.read(key: 'driver_token');
      debugPrint('=== LOGIN SUCCESS ===');
      debugPrint('Driver: ${result.driver.name} (id=${result.driver.id})');
      debugPrint('Token stored: ${storedToken != null ? 'YES (${storedToken.substring(0, 20)}...)' : 'NO'}');

      ref.read(currentDriverProvider.notifier).state = result.driver;

      // Restore any active trip that was left running (e.g. app was killed)
      try {
        final active = await ApiService.instance.fetchActiveAssignment();
        if (active != null && mounted) {
          ref.read(activeTripProvider.notifier).setActiveTrip(
            assignment:  active,
            firebaseKey: active.firebaseTripKey ?? '',
          );
        }
      } catch (_) {
        // Non-fatal — just means no active trip to restore
      }

      if (mounted) context.go('/trips');
    } catch (e) {
      debugPrint('=== LOGIN FAILED: $e ===');
      setState(() {
        _loading = false;
        _error   = 'بيانات الدخول غير صحيحة';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blueDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // ── Logo ──────────────────────────────────────
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.directions_bus_rounded,
                    color: AppColors.blue, size: 50),
              ),

              const SizedBox(height: 20),

              const Text('Rio Captain',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                  )),

              const SizedBox(height: 6),

              Text('نادي ريو — تطبيق السائق',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  )),

              const SizedBox(height: 48),

              // ── Card ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('تسجيل الدخول',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.blueDeep,
                        )),
                    const SizedBox(height: 24),

                    // Username
                    _field(
                      controller: _userCtrl,
                      label: 'اسم المستخدم',
                      icon: Icons.person_outline,
                      textDirection: TextDirection.ltr,
                    ),
                    const SizedBox(height: 16),

                    // Password
                    _field(
                      controller: _passCtrl,
                      label: 'كلمة المرور',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSub,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      onSubmit: (_) => _login(),
                    ),

                    // Remember me
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => setState(() => _remember = !_remember),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: _remember ? AppColors.blue : Colors.transparent,
                              border: Border.all(
                                color: _remember ? AppColors.blue : AppColors.textSub,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: _remember
                                ? const Icon(Icons.check, color: Colors.white, size: 14)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'تذكّرني',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: AppColors.textSub,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: AppColors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Button
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                            : const Text('دخول',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            )),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              Text('نادي ريو الرياضي © ${DateTime.now().year}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextDirection? textDirection,
    ValueChanged<String>? onSubmit,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        textDirection: textDirection,
        textAlign: TextAlign.right,
        onSubmitted: onSubmit,
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontFamily: 'Cairo', color: AppColors.textSub, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.blue, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.base,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}