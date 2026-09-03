import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/encryption/key_manager.dart';
import '../../../shared/theme/app_palette.dart';

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _currentPinCtrl = PinInputController();
  final _newPinCtrl = PinInputController();
  final _confirmPinCtrl = PinInputController();

  // Step 0: verify current PIN, Step 1: enter new PIN, Step 2: confirm new PIN
  int _step = 0;
  String _newPin = '';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyCurrentPin(String pin) async {
    setState(() { _loading = true; _error = null; });
    final valid = await AuthService.instance.verifyPIN(pin);
    if (!mounted) return;
    if (valid) {
      setState(() {
        _step = 1;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = 'Current PIN is incorrect';
        _currentPinCtrl.clear();
      });
    }
  }

  void _onNewPinComplete(String pin) {
    setState(() {
      _newPin = pin;
      _step = 2;
      _error = null;
    });
  }

  Future<void> _onConfirmPinComplete(String pin) async {
    if (pin != _newPin) {
      setState(() {
        _error = 'PINs do not match. Please try again.';
        _step = 1;
        _newPin = '';
        _newPinCtrl.clear();
        _confirmPinCtrl.clear();
      });
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await KeyManager.instance.changePIN(pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN changed successfully')));
        context.pop();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to change PIN: $e';
        _step = 1;
        _newPin = '';
        _newPinCtrl.clear();
        _confirmPinCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('Change PIN')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your PIN protects access to your vault.',
                style: TextStyle(color: context.palette.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildStep(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: context.palette.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(color: context.palette.error, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 24),
                Center(child: CircularProgressIndicator(color: context.palette.primary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepWidget(
          key: const ValueKey(0),
          title: 'Enter current PIN',
          subtitle: 'Verify your identity before changing your PIN.',
          ctrl: _currentPinCtrl,
          onCompleted: _verifyCurrentPin,
        );
      case 1:
        return _StepWidget(
          key: const ValueKey(1),
          title: 'Enter new PIN',
          subtitle: 'Choose a new 6-digit PIN.',
          ctrl: _newPinCtrl,
          onCompleted: _onNewPinComplete,
        );
      case 2:
        return _StepWidget(
          key: const ValueKey(2),
          title: 'Confirm new PIN',
          subtitle: 'Enter your new PIN again to confirm.',
          ctrl: _confirmPinCtrl,
          onCompleted: _onConfirmPinComplete,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _StepWidget extends StatelessWidget {
  final String title;
  final String subtitle;
  final PinInputController ctrl;
  final void Function(String) onCompleted;

  const _StepWidget({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ctrl,
    required this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(
                color: context.palette.textSecondary, fontSize: 13)),
        const SizedBox(height: 28),
        MaterialPinField(
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
        ),
      ],
    );
  }
}
