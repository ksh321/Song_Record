import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/database/account_store.dart';
import '../../../core/domain/identifiers.dart';
import '../../../core/sync/snapshot_transport.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/auth_session.dart';
import '../export/export_preparation.dart';
import 'import_application.dart';
import 'import_apply_preview.dart';
import 'import_candidates.dart';
import 'import_conflicts.dart';
import 'import_decision.dart';
import 'import_decision_screen.dart';
import 'import_identity.dart';
import 'import_preflight.dart';
import 'import_validation.dart';
import 'import_zip.dart';

/// Select a real document and enter the existing verified import preview.
/// No example backup or unverified server state can enter this route.
class ImportEntryScreen extends StatefulWidget {
  const ImportEntryScreen({
    required this.store,
    required this.transport,
    required this.session,
    required this.requireCurrent,
    this.accountChanges,
    this.synchronize,
    super.key,
  });
  final AccountStore store;
  final SnapshotTransport transport;
  final Future<AuthSession> Function() session;
  final VoidCallback requireCurrent;
  final Listenable? accountChanges;
  final Future<void> Function()? synchronize;
  @override
  State<ImportEntryScreen> createState() => _State();
}

class _State extends State<ImportEntryScreen> {
  bool busy = false;
  String? message;
  int generation = 0;
  ImportDecision? activeDecision;
  final progress = ValueNotifier<String?>(null);
  void invalidate() {
    generation++;
    activeDecision?.cancel();
    progress.value = null;
    if (mounted) {
      setState(() {
        busy = false;
        message = '계정이 바뀌었습니다. 현재 계정에서 백업을 다시 선택해 주세요.';
      });
    }
  }

  void accountChanged() {
    try {
      widget.requireCurrent();
    } catch (_) {
      invalidate();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.accountChanges?.addListener(accountChanged);
  }

  @override
  void didUpdateWidget(covariant ImportEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountChanges != widget.accountChanges) {
      oldWidget.accountChanges?.removeListener(accountChanged);
      widget.accountChanges?.addListener(accountChanged);
    }
    if (oldWidget.store != widget.store) invalidate();
  }

  static const channel = MethodChannel('song_record/backup_import');
  Future<void> select() async {
    if (busy) return;
    final epoch = ++generation;
    void guard() {
      widget.requireCurrent();
      if (!mounted || epoch != generation) throw StateError('Import cancelled');
    }

    setState(() {
      busy = true;
      message = null;
    });
    ImportDecision? decision;
    try {
      guard();
      final path = await channel.invokeMethod<String>('pickZip');
      guard();
      if (path == null) return;
      final cache = await getTemporaryDirectory();
      final staged = await ImportZipReader(
        requireCurrent: guard,
        availableBytes: AndroidBackupSpace.availableBytes,
      ).unpack(File(path), cache);
      guard();
      decision = ImportDecision(
        requireCurrent: guard,
        validate: (fence) => ImportValidator(
          owner: widget.store.userId,
          requireCurrent: fence,
          audio: AndroidImportAudioProbe(),
        ).verify(staged),
      );
      final active = decision;
      activeDecision = active;
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => ImportDecisionScreen(
            controller: active,
            progress: progress,
            onCancel: () => Navigator.pop(context),
            onApproved: (consent) async {
              try {
                void consentGuard() {
                  guard();
                  active.requireConsent(consent);
                }

                consentGuard();
                progress.value = '현재 계정의 최신 정보 확인 중';
                final preflight = ImportPreflight(
                  store: widget.store,
                  transport: widget.transport,
                  session: widget.session,
                  requireCurrent: consentGuard,
                  clock: () => DateTime.now().toUtc(),
                );
                Future<ImportServerBaseline> refresh() async {
                  final token = await preflight.request(
                    consent.source.manifest,
                    UuidValue.random().value,
                  );
                  final deadline = DateTime.now().add(
                    const Duration(minutes: 2),
                  );
                  while (true) {
                    consentGuard();
                    try {
                      return await preflight.readReady(token);
                    } on ImportNotReady {
                      if (DateTime.now().isAfter(deadline)) rethrow;
                      await Future<void>.delayed(const Duration(seconds: 2));
                    }
                  }
                }

                final sync = widget.synchronize;
                if (sync != null) {
                  await sync();
                  consentGuard();
                }
                final server = await refresh();
                final identity = planImportIdentities(
                  consent: consent,
                  server: server,
                  requireCurrent: consentGuard,
                );
                final candidates = planImportCandidates(
                  identity,
                  requireCurrent: consentGuard,
                );
                final preview = await previewImportConflicts(
                  consent: consent,
                  candidates: candidates,
                  server: server,
                  store: widget.store,
                  requireCurrent: consentGuard,
                );
                consentGuard();
                progress.value = null;
                if (!context.mounted) return;
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _AccountFence(
                      changes: Listenable.merge([
                        widget.accountChanges,
                        active,
                      ]),
                      guard: consentGuard,
                      child: ImportApplyPreview(
                        information: preview.records.length,
                        files: preview.fileIds.length,
                        held:
                            identity.blocked.length +
                            identity.held.length +
                            candidates.held.length,
                        conflicts: preview.conflicts.length,
                        requireCurrent: consentGuard,
                        accountChanges: Listenable.merge([
                          widget.accountChanges,
                          active,
                        ]),
                        apply: sync == null
                            ? null
                            : (pageGuard) => applyReviewedImport(
                                store: widget.store,
                                consent: consent,
                                preview: preview,
                                server: server,
                                archive: File(path),
                                synchronize: sync,
                                refresh: refresh,
                                requireCurrent: pageGuard,
                                held:
                                    identity.blocked.length +
                                    identity.held.length +
                                    candidates.held.length,
                              ),
                      ),
                    ),
                  ),
                );
              } catch (_) {
                if (context.mounted && epoch == generation) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('대조하지 못했어요. 계정·연결 상태를 확인하고 다시 선택해 주세요.'),
                    ),
                  );
                }
              } finally {
                if (mounted && epoch == generation) progress.value = null;
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted && epoch == generation) {
        setState(
          () => message = '파일·공간·로그인 상태를 확인해 주세요. 기존 정보와 파일은 변경하지 않았습니다.',
        );
      }
    } finally {
      decision?.dispose();
      if (identical(activeDecision, decision)) activeDecision = null;
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    widget.accountChanges?.removeListener(accountChanged);
    activeDecision?.cancel();
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('백업 가져오기')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const Text(
            '동일 계정으로 로그인하고 온라인에서 최신 삭제 상태부터 확인합니다. 검사 실패 시 기존 정보와 정상 파일을 변경하지 않습니다.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          FilledButton(
            onPressed: busy ? null : () => unawaited(select()),
            child: const Text('백업 ZIP 선택'),
          ),
        ],
      ),
    ),
  );
}

class _AccountFence extends StatelessWidget {
  const _AccountFence({
    required this.changes,
    required this.guard,
    required this.child,
  });
  final Listenable? changes;
  final VoidCallback guard;
  final Widget child;
  Widget guarded() {
    try {
      guard();
      return child;
    } catch (_) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('계정이 바뀌었습니다. 설정으로 돌아가 주세요.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => changes == null
      ? guarded()
      : ListenableBuilder(listenable: changes!, builder: (_, _) => guarded());
}
