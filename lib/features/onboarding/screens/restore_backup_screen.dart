import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/providers/backup_providers.dart';
import '../../../core/providers/vault_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../router/app_router.dart';
import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/confirm_dialog.dart';

class RestoreBackupScreen extends ConsumerStatefulWidget {
  final File? initialFile;
  final bool isFromSettings;
  final bool isMergeMode;

  const RestoreBackupScreen({
    super.key,
    this.initialFile,
    this.isFromSettings = false,
    this.isMergeMode = false,
  });

  @override
  ConsumerState<RestoreBackupScreen> createState() =>
      _RestoreBackupScreenState();
}

class _RestoreBackupScreenState extends ConsumerState<RestoreBackupScreen> {
  File? _selectedFile;
  BackupHeaderInfo? _headerInfo;
  bool _readingHeader = false;
  bool _restoring = false;
  String? _error;

  // Unlock mode: 0 = PIN, 1 = Recovery Phrase
  int _unlockMode = 0;

  final _pinCtrl = PinInputController();
  final _phraseCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _loadFile(widget.initialFile!);
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _phraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (result.isNotEmpty && result.first.path != null) {
        final file = File(result.first.path!);
        await _loadFile(file);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to pick file: $e';
      });
    }
  }

  Future<void> _loadFile(File file) async {
    setState(() {
      _selectedFile = file;
      _readingHeader = true;
      _error = null;
      _headerInfo = null;
    });

    try {
      final header = await BackupService.instance.readBackupHeader(file);
      setState(() {
        _headerInfo = header;
        _readingHeader = false;
        if (!header.hasPin && header.hasRecoveryKey) {
          _unlockMode = 1;
        } else {
          _unlockMode = 0;
        }
      });
    } catch (e) {
      setState(() {
        _readingHeader = false;
        _error = e is FormatException ? e.message : 'Invalid backup file: $e';
      });
    }
  }

  Future<ImportConflictResolution?> _showConflictPolicySheet(
      BuildContext context) {
    return showModalBottomSheet<ImportConflictResolution>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _ConflictPolicySheet(),
    );
  }

  Future<void> _restore() async {
    if (_selectedFile == null) return;

    final pin = _unlockMode == 0 ? _pinCtrl.text.trim() : null;
    final phrase = _unlockMode == 1 ? _phraseCtrl.text.trim() : null;

    if (_unlockMode == 0 && (pin == null || pin.isEmpty)) {
      setState(() => _error = 'Please enter the backup PIN.');
      return;
    }

    if (_unlockMode == 1 && (phrase == null || phrase.isEmpty)) {
      setState(() => _error = 'Please enter the recovery phrase.');
      return;
    }

    ImportConflictResolution resolution = ImportConflictResolution.keepBoth;
    if (widget.isMergeMode) {
      final selectedPolicy = await _showConflictPolicySheet(context);
      if (selectedPolicy == null || !mounted) return;
      resolution = selectedPolicy;
    } else {
      final confirm = await showConfirmDialog(
        context,
        title: 'Full Restore Warning',
        message:
            '⚠️ Restoring will ERASE all current vault data and replace everything with the backup file.\n\nAre you sure you want to proceed?',
        confirmText: 'Erase & Restore',
        destructive: true,
      );
      if (!confirm || !mounted) return;
    }

    setState(() {
      _restoring = true;
      _error = null;
    });

    try {
      if (widget.isMergeMode) {
        final result = await BackupService.instance.mergeFromBackup(
          file: _selectedFile!,
          pin: pin,
          recoveryPhrase: phrase,
          conflictResolution: resolution,
        );

        ref.invalidate(vaultCountsProvider);
        ref.invalidate(documentsProvider);
        ref.invalidate(notesProvider);
        ref.invalidate(passwordsProvider);
        ref.invalidate(pagesProvider);
        ref.invalidate(backupLogsProvider);
        ref.invalidate(lastBackupProvider);

        if (!mounted) return;

        final message = result.skippedCount > 0
            ? 'Vault merged: ${result.totalItems} items (${result.updatedCount} updated, ${result.skippedCount} skipped)'
            : 'Vault merged successfully (${result.totalItems} items imported)';

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: context.palette.success,
              duration: const Duration(seconds: 10),
              behavior: SnackBarBehavior.floating,
            ),
          );
      } else {
        final result = await BackupService.instance.restoreFromBackup(
          file: _selectedFile!,
          pin: pin,
          recoveryPhrase: phrase,
        );

        // Refresh auth state and vault providers
        await ref.read(authStateProvider.notifier).markAuthenticated();
        ref.invalidate(vaultCountsProvider);
        ref.invalidate(documentsProvider);
        ref.invalidate(notesProvider);
        ref.invalidate(passwordsProvider);
        ref.invalidate(pagesProvider);
        ref.invalidate(backupLogsProvider);
        ref.invalidate(lastBackupProvider);

        if (!mounted) return;

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Vault restored successfully (${result.totalItems} items recovered)',
              ),
              backgroundColor: context.palette.success,
              duration: const Duration(seconds: 10),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }

      if (!widget.isMergeMode) {
        context.go(AppRoutes.home);
      } else if (widget.isFromSettings && context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      setState(() {
        _restoring = false;
        _error = e
            .toString()
            .replaceFirst('AuthenticationException: ', '')
            .replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText =
        widget.isMergeMode ? 'Import Backup (Merge)' : 'Restore Vault (Reset)';
    final subtitleText = widget.isMergeMode
        ? 'Select a .cipherbox backup file to merge documents, passwords, notes, and pages into your current vault without deleting existing items.'
        : 'Select a .cipherbox backup file to restore all your documents, passwords, notes, and pages. Existing data will be replaced.';

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: Text(titleText),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.welcome);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isMergeMode
                    ? 'Import & Merge Data'
                    : 'Restore from Backup',
                style: TextStyle(
                  color: context.palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitleText,
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              if (_selectedFile == null) ...[
                _buildPickFileCard(),
              ] else ...[
                _buildFileInfoCard(),
                const SizedBox(height: 20),
                if (_headerInfo != null) ...[
                  _buildUnlockCard(),
                  const SizedBox(height: 24),
                  _buildRestoreButton(),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildErrorCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickFileCard() {
    return InkWell(
      onTap: _readingHeader ? null : _pickFile,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.palette.primary.withValues(alpha: 0.4),
            style: BorderStyle.solid,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.isMergeMode
                    ? Icons.file_download_outlined
                    : Icons.restore_page_outlined,
                color: context.palette.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Backup File',
              style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to browse (.cipherbox)',
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileInfoCard() {
    final fileName = _selectedFile!.uri.pathSegments.last;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  color: context.palette.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fileName,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Choose another file',
                color: context.palette.textSecondary,
                onPressed: _restoring ? null : _pickFile,
              ),
            ],
          ),
          if (_readingHeader) ...[
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.palette.primary),
              ),
            ),
          ] else if (_headerInfo != null) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Created: ${DateFormatter.formatDateTime(_headerInfo!.createdAt)}',
                  style: TextStyle(
                      color: context.palette.textSecondary, fontSize: 12),
                ),
                Text(
                  FileSizeFormatter.format(_headerInfo!.fileSize),
                  style: TextStyle(
                      color: context.palette.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _countBadge(
                    '📄 ${_headerInfo!.itemCounts['documents'] ?? 0} Docs'),
                _countBadge(
                    '🔑 ${_headerInfo!.itemCounts['passwords'] ?? 0} Passwords'),
                _countBadge(
                    '📝 ${_headerInfo!.itemCounts['notes'] ?? 0} Notes'),
                _countBadge(
                    '📑 ${_headerInfo!.itemCounts['pages'] ?? 0} Pages'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.palette.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.palette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: context.palette.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildUnlockCard() {
    final hasPin = _headerInfo?.hasPin ?? true;
    final hasRecovery = _headerInfo?.hasRecoveryKey ?? true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Decrypt Backup',
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (hasPin && hasRecovery) ...[
            Container(
              decoration: BoxDecoration(
                color: context.palette.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TabButton(
                      label: 'App PIN',
                      icon: Icons.pin_outlined,
                      selected: _unlockMode == 0,
                      onTap: () => setState(() => _unlockMode = 0),
                    ),
                  ),
                  Expanded(
                    child: _TabButton(
                      label: 'Recovery Key',
                      icon: Icons.vpn_key_outlined,
                      selected: _unlockMode == 1,
                      onTap: () => setState(() => _unlockMode = 1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_unlockMode == 0) ...[
            Text(
              'Enter the PIN when backup was created:',
              style:
                  TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            MaterialPinField(
              length: 6,
              pinController: _pinCtrl,
              obscureText: true,
              theme: MaterialPinTheme(
                shape: MaterialPinShape.outlined,
                cellSize: const Size(42, 48),
                borderRadius: BorderRadius.circular(8),
                fillColor: context.palette.background,
                focusedFillColor: context.palette.surfaceLight,
                focusedBorderColor: context.palette.primary,
                borderColor: context.palette.border,
              ),
              onChanged: (_) {},
            ),
          ] else ...[
            Text(
              'Enter 32-character Cipher Recovery Key:',
              style:
                  TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phraseCtrl,
              style: TextStyle(
                color: context.palette.textPrimary,
                fontFamily: 'monospace',
                letterSpacing: 1.2,
                fontSize: 14,
              ),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                hintStyle: TextStyle(
                  color: context.palette.textSecondary,
                  fontFamily: 'monospace',
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRestoreButton() {
    final buttonText = widget.isMergeMode
        ? 'Import & Merge Vault'
        : 'Restore Vault (Erase & Replace)';

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _restoring ? null : _restore,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: widget.isMergeMode
              ? context.palette.primary
              : context.palette.error,
        ),
        child: _restoring
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(buttonText),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
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
            child: Text(
              _error!,
              style: TextStyle(color: context.palette.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictPolicySheet extends StatefulWidget {
  const _ConflictPolicySheet();

  @override
  State<_ConflictPolicySheet> createState() => _ConflictPolicySheetState();
}

class _ConflictPolicySheetState extends State<_ConflictPolicySheet> {
  ImportConflictResolution _selected = ImportConflictResolution.keepBoth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.merge_type_rounded,
                    color: context.palette.primary, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Duplicate Items Policy',
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'How should duplicate titles or matching items be handled?',
              style:
                  TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _policyOption(
              title: 'Keep Both (Create Copies)',
              subtitle:
                  'Adds "(Imported)" suffix to duplicate items. 100% safe, no existing data is replaced.',
              icon: Icons.copy_all_outlined,
              value: ImportConflictResolution.keepBoth,
              isRecommended: true,
            ),
            const SizedBox(height: 10),
            _policyOption(
              title: 'Overwrite Existing',
              subtitle:
                  'Replaces current matching vault items with backup versions.',
              icon: Icons.sync_alt_outlined,
              value: ImportConflictResolution.overwrite,
            ),
            const SizedBox(height: 10),
            _policyOption(
              title: 'Skip Duplicates',
              subtitle:
                  'Keeps your current items and skips importing duplicates.',
              icon: Icons.skip_next_outlined,
              value: ImportConflictResolution.skip,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: context.palette.border),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: context.palette.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: context.palette.primary,
                    ),
                    child: const Text('Start Import'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _policyOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required ImportConflictResolution value,
    bool isRecommended = false,
  }) {
    final isSelected = _selected == value;
    return InkWell(
      onTap: () => setState(() => _selected = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? context.palette.primary.withValues(alpha: 0.1)
              : context.palette.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? context.palette.primary
                : context.palette.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected
                  ? context.palette.primary
                  : context.palette.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.palette.success
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Recommended',
                            style: TextStyle(
                              color: context.palette.success,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: context.palette.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? context.palette.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(
                  color: context.palette.primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? context.palette.primary
                  : context.palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? context.palette.primary
                    : context.palette.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
