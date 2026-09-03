import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/auth/pin_service.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../router/app_router.dart';
import '../../../shared/theme/app_palette.dart';

class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen>
    with SingleTickerProviderStateMixin {
  final _pinController = PinInputController();
  late final AnimationController _shakeController;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _onPINComplete(String pin) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final pinService = PINService.instance;

    if (pinService.isLocked) {
      setState(() {
        _error = 'Too many attempts. Use recovery phrase to reset.';
        _loading = false;
      });
      _shakeController.forward(from: 0);
      return;
    }

    final success = await pinService.verifyPIN(pin);
    if (!mounted) return;

    if (success) {
      await ref.read(authStateProvider.notifier).markAuthenticated();
      if (!mounted) return;
      setState(() => _loading = false);
    } else {
      final remaining = PINService.maxAttempts - pinService.failedAttempts;
      _pinController.clear();
      setState(() {
        _error = pinService.isLocked
            ? 'Too many failed attempts.'
            : 'Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.';
        _loading = false;
      });
      _shakeController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinService = PINService.instance;

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Icon(Icons.lock_outline_rounded,
                        color: context.palette.primary, size: 56)
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(
                        begin: const Offset(0.8, 0.8),
                        duration: 500.ms,
                        curve: Curves.easeOutBack),
                const SizedBox(height: 24),
                Text(
                  'Enter PIN',
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
                const SizedBox(height: 8),
                Text(
                  'Enter your PIN to unlock CipherBox',
                  style:
                      TextStyle(color: context.palette.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 250.ms, duration: 400.ms),
                const SizedBox(height: 48),
                Center(
                  child: Animate(
                    autoPlay: false,
                    controller: _shakeController,
                    onComplete: (c) => c.reset(),
                    effects: const [ShakeEffect(hz: 4, offset: Offset(6, 0))],
                    child: MaterialPinField(
                      length: 6,
                      pinController: _pinController,
                      obscureText: true,
                      enabled: !pinService.isLocked && !_loading,
                      mainAxisAlignment: MainAxisAlignment.center,
                      theme: MaterialPinTheme(
                        shape: MaterialPinShape.outlined,
                        cellSize: const Size(44, 52),
                        borderRadius: BorderRadius.circular(10),
                        fillColor: context.palette.surface,
                        focusedFillColor: context.palette.surfaceLight,
                        focusedBorderColor: context.palette.primary,
                        borderColor: context.palette.border,
                      ),
                      onChanged: (_) => setState(() => _error = null),
                      onCompleted: _onPINComplete,
                    ),
                  ).animate().fadeIn(delay: 350.ms, duration: 400.ms),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          color: context.palette.error, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: context.palette.error, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_loading) ...[
                  const SizedBox(height: 20),
                  CircularProgressIndicator(
                      color: context.palette.primary, strokeWidth: 2),
                ],
                const Spacer(flex: 2),
                TextButton(
                  onPressed: () => context.go(AppRoutes.recoveryEntry),
                  child: Text('Forgot PIN? Recover vault',
                      style: TextStyle(
                          color: context.palette.textSecondary, fontSize: 13)),
                ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
