import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../router/app_router.dart';
import '../../../shared/theme/app_palette.dart';

class SetupPinScreen extends ConsumerStatefulWidget {
  const SetupPinScreen({super.key});

  @override
  ConsumerState<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends ConsumerState<SetupPinScreen> {
  final _pinCtrl = PinInputController();
  final _confirmCtrl = PinInputController();
  String _firstPin = '';
  bool _confirming = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _onFirstPinComplete(String pin) {
    setState(() {
      _firstPin = pin;
      _confirming = true;
      _error = null;
    });
  }

  Future<void> _onConfirmPinComplete(String pin) async {
    if (pin != _firstPin) {
      setState(() {
        _error = 'PINs do not match. Please try again.';
        _confirming = false;
        _firstPin = '';
        _pinCtrl.clear();
        _confirmCtrl.clear();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final recoveryPhrase =
        await ref.read(authStateProvider.notifier).createAccount(pin: pin);

    if (!mounted) return;

    if (recoveryPhrase != null) {
      context.go(AppRoutes.setupRecovery, extra: recoveryPhrase);
    } else {
      final error = ref.read(authStateProvider).error;
      setState(() {
        _loading = false;
        _error = error ?? 'Failed to create vault. Please try again.';
        _confirming = false;
        _firstPin = '';
        _pinCtrl.clear();
        _confirmCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text(
                'CipherBox',
                style: TextStyle(
                  color: context.palette.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 40),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _confirming ? _buildConfirmStep() : _buildCreateStep(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: context.palette.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: context.palette.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: context.palette.error, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 32),
                Center(
                    child: CircularProgressIndicator(color: context.palette.primary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateStep() {
    return Column(
      key: const ValueKey('create'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create your PIN',
          style: TextStyle(
            color: context.palette.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a 6-digit PIN to protect your vault. You\'ll enter this every time you open CipherBox.',
          style: TextStyle(
              color: context.palette.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 40),
        _pinField(_pinCtrl, _onFirstPinComplete),
        const SizedBox(height: 16),
        Text(
          'Use a PIN you\'ll remember — it cannot be recovered without your recovery phrase.',
          style: TextStyle(
              color: context.palette.textSecondary, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      key: const ValueKey('confirm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm your PIN',
          style: TextStyle(
            color: context.palette.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your PIN again to confirm.',
          style: TextStyle(
              color: context.palette.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 40),
        _pinField(_confirmCtrl, _onConfirmPinComplete),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            setState(() {
              _confirming = false;
              _firstPin = '';
              _pinCtrl.clear();
              _confirmCtrl.clear();
              _error = null;
            });
          },
          child: Text('← Change PIN',
              style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _pinField(
      PinInputController ctrl, void Function(String) onCompleted) {
    return MaterialPinField(
      length: 6,
      pinController: ctrl,
      obscureText: true,
      theme: MaterialPinTheme(
        shape: MaterialPinShape.outlined,
        cellSize: const Size(44, 52),
        borderRadius: BorderRadius.circular(10),
        fillColor: context.palette.background,
        focusedFillColor: context.palette.surfaceLight,
        focusedBorderColor: context.palette.primary,
        borderColor: context.palette.border,
      ),
      onChanged: (_) {},
      onCompleted: onCompleted,
    );
  }
}
