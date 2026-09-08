import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> authenticate(
      {String reason = 'Authenticate to unlock CipherBox'}) async {
    try {
      debugPrint(
          '[BiometricService] Starting authentication with reason: $reason');
      final result = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      debugPrint('[BiometricService] Authentication result: $result');
      return result;
    } catch (e) {
      debugPrint('[BiometricService] Authentication error: $e');
      return false;
    }
  }

  Future<bool> authenticateForReveal() async {
    return authenticate(reason: 'Authenticate to reveal sensitive data');
  }

  Future<void> stopAuthentication() async {
    await _auth.stopAuthentication();
  }
}
