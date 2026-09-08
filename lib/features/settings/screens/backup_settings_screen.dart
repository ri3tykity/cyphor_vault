import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/providers/backup_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../router/app_router.dart';
import '../../../shared/theme/app_palette.dart';

class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastBackup = ref.watch(lastBackupProvider);
    final status = ref.watch(backupStatusProvider);

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          lastBackup.when(
            data: (log) => _StatusCard(
              log == null
                  ? 'No backup created yet'
                  : 'Last backup: ${DateFormatter.formatRelative(log.backupDate)}',
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          if (status == BackupStatus.inProgress) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(color: context.palette.primary),
          ],
          const SizedBox(height: 16),
          _Card(children: [
            ListTile(
              leading: Icon(Icons.download_rounded, color: context.palette.primary),
              title: Text('Export Backup File',
                  style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Save encrypted .cipherbox to Downloads or selected folder and share',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: status == BackupStatus.inProgress ? null : () => _exportBackup(context, ref),
            ),
            Divider(color: context.palette.border, height: 1),
            ListTile(
              leading: Icon(Icons.file_download_outlined, color: context.palette.primary),
              title: Text('Import Backup (Merge)',
                  style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Merge documents, notes, passwords, and pages from backup into current vault',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: status == BackupStatus.inProgress
                  ? null
                  : () => context.push(
                        AppRoutes.restoreBackup,
                        extra: {
                          'isFromSettings': true,
                          'isMergeMode': true,
                        },
                      ),
            ),
            Divider(color: context.palette.border, height: 1),
            ListTile(
              leading: Icon(Icons.restore_page_outlined, color: context.palette.warning),
              title: Text('Restore Vault (Reset & Replace)',
                  style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Erase all current data and restore completely from a backup file',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: status == BackupStatus.inProgress
                  ? null
                  : () => context.push(
                        AppRoutes.restoreBackup,
                        extra: {
                          'isFromSettings': true,
                          'isMergeMode': false,
                        },
                      ),
            ),
          ]),
          const SizedBox(height: 16),
          _Card(children: [
            ListTile(
              leading: Icon(Icons.cloud_outlined, color: context.palette.textSecondary),
              title: Text('Cloud & Drive Storage',
                  style: TextStyle(color: context.palette.textPrimary)),
              subtitle: Text('Export and save backups to Google Drive, iCloud or storage',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
              onTap: () => _showCloudBackupInfo(context),
            ),
          ]),
          const SizedBox(height: 24),
          _BackupLogsSection(ref: ref),
        ],
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Export Vault Backup',
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.download_rounded, color: context.palette.primary, size: 20),
                ),
                title: Text('Save to Downloads Folder',
                    style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text('Directly saves .cipherbox to standard Downloads folder',
                    style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'downloads'),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.folder_open_rounded, color: context.palette.primary, size: 20),
                ),
                title: Text('Choose Custom Folder...',
                    style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text('Select a specific directory on your device',
                    style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    String? customDir;
    if (choice == 'custom') {
      try {
        customDir = await FilePicker.getDirectoryPath();
        if (customDir == null || !context.mounted) return;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open folder picker: $e'),
              backgroundColor: context.palette.error,
            ),
          );
        }
        return;
      }
    }

    ref.read(backupStatusProvider.notifier).setInProgress();
    try {
      final result = await BackupService.instance.exportBackup(
        targetDirectoryPath: customDir,
      );
      ref.read(backupStatusProvider.notifier).setSuccess();
      ref.invalidate(lastBackupProvider);
      ref.invalidate(backupLogsProvider);

      if (!context.mounted) return;

      // Show dialog with file details and share prompt
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.palette.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: context.palette.success, size: 24),
              const SizedBox(width: 10),
              Text(
                'Backup Saved',
                style: TextStyle(
                  color: context.palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Encrypted backup created with ${result.totalItems} items.',
                style: TextStyle(color: context.palette.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                'Saved location:',
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.palette.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.palette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined,
                        color: context.palette.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.file.path,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: context.palette.textPrimary,
                          fontSize: 12,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Done', style: TextStyle(color: context.palette.textSecondary)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Share File'),
              onPressed: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(result.file.path, mimeType: 'application/octet-stream')],
                    subject: 'Cyphor Vault Backup',
                    text: 'Encrypted Cyphor Vault backup file',
                  ),
                );
              },
            ),
          ],
        ),
      );

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Backup saved (${result.totalItems} items)'),
            backgroundColor: context.palette.success,
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () {
                SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(result.file.path, mimeType: 'application/octet-stream')],
                    subject: 'Cyphor Vault Backup',
                    text: 'Encrypted Cyphor Vault backup file',
                  ),
                );
              },
            ),
          ),
        );
    } catch (e) {
      ref.read(backupStatusProvider.notifier).setFailed();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Backup failed: $e'),
              backgroundColor: context.palette.error,
              duration: const Duration(seconds: 10),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
  }

  void _showCloudBackupInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.palette.surface,
        title: Text('Cloud & Drive Storage', style: TextStyle(color: context.palette.textPrimary)),
        content: Text(
          'Your backup file (.cipherbox) is fully encrypted with zero-knowledge AES-256-GCM.\n\nYou can safely save or upload your backup files to Google Drive, iCloud Drive, Nextcloud, local storage, or email using the "Export Backup File" option.',
          style: TextStyle(color: context.palette.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: context.palette.primary)),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String message;
  const _StatusCard(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: context.palette.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(children: children),
    );
  }
}

class _BackupLogsSection extends StatelessWidget {
  final WidgetRef ref;
  const _BackupLogsSection({required this.ref});

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(backupLogsProvider);
    return logs.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Recent Backup History',
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _Card(
              children: items.take(5).map((log) => ListTile(
                leading: Icon(
                  log.status == 'success' ? Icons.check_circle_outline : Icons.error_outline,
                  color: log.status == 'success' ? context.palette.success : context.palette.error,
                  size: 18,
                ),
                title: Text(
                  DateFormatter.formatDateTime(log.backupDate),
                  style: TextStyle(color: context.palette.textPrimary, fontSize: 14),
                ),
                subtitle: Text(
                  '${log.destination} · ${FileSizeFormatter.format(log.fileSize)} · ${log.itemCount} items',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 12),
                ),
              )).toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
