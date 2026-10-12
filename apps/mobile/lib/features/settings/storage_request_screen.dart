import 'package:flutter/material.dart';

import '../../core/domain/identifiers.dart';

import 'storage_request_outbox.dart';

class StorageRequestScreen extends StatefulWidget {
  const StorageRequestScreen({
    required this.outbox,
    required this.loadHistory,
    super.key,
  });
  final StorageRequestOutbox outbox;
  final Future<List<Map<String, dynamic>>> Function() loadHistory;
  @override
  State<StorageRequestScreen> createState() => _DemandState();
}

class _DemandState extends State<StorageRequestScreen> {
  final selected = <String>{};
  List<Map<String, dynamic>>? history;
  bool reading = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final epoch = ++generation;
    setState(() {
      reading = true;
      history = null;
    });
    try {
      widget.outbox.guard();
      final values = await widget.loadHistory();
      widget.outbox.guard();
      for (final row in values) {
        UuidValue(row['id'] as String);
        final types = (row['types'] as List).cast<String>();
        if (types.isEmpty ||
            types.toSet().length != types.length ||
            !types.every({'PIN_LIMIT', 'STORAGE_QUOTA'}.contains) ||
            row['status'] != 'RECEIVED' ||
            DateTime.tryParse(row['received_at'] as String? ?? '') == null) {
          throw const FormatException('Invalid demand history');
        }
      }
      if (mounted && epoch == generation) {
        setState(() {
          history = values;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && epoch == generation) {
        setState(() => error = '접수 이력을 확인하지 못했어요. 기기 전송 대기는 보존됩니다.');
      }
    } finally {
      if (mounted && epoch == generation) setState(() => reading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.outbox,
    builder: (c, _) {
      try {
        widget.outbox.guard();
      } catch (_) {
        return Scaffold(
          appBar: AppBar(title: const Text('추가 보관 요청')),
          body: const SafeArea(
            child: Center(child: Text('로그인 상태가 바뀌었어요. 설정을 다시 열어 주세요.')),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('추가 보관 요청')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '고정 개수와 파일 보관 용량은 다른 한도입니다. 현재 부족하지 않아도 필요한 종류를 하나 이상 선택해 요청할 수 있어요. 요청만으로 한도는 늘어나지 않습니다.',
              ),
              for (final entry in const {
                'PIN_LIMIT': '고정 개수가 더 필요해요',
                'STORAGE_QUOTA': '파일 보관 용량이 더 필요해요',
              }.entries)
                CheckboxListTile(
                  title: Text(entry.value),
                  value: selected.contains(entry.key),
                  onChanged: widget.outbox.working
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            selected.add(entry.key);
                          } else {
                            selected.remove(entry.key);
                          }
                        }),
                ),
              FilledButton(
                onPressed:
                    !widget.outbox.ready ||
                        widget.outbox.working ||
                        selected.isEmpty
                    ? null
                    : () async {
                        await widget.outbox.submit(selected);
                        if (mounted) reload();
                      },
                child: const Text('새 요청 제출'),
              ),
              if (widget.outbox.working || reading)
                const LinearProgressIndicator(),
              if (widget.outbox.message != null) Text(widget.outbox.message!),
              for (final item in widget.outbox.items)
                ListTile(
                  title: Text(
                    item['state'] == 'PENDING' ? '전송 대기' : '접수되지 않은 요청',
                  ),
                  subtitle: Text(
                    item['error'] == 'STORAGE_REQUEST_EXPIRED'
                        ? '기존 번호 만료 · 새 제출은 새 요청'
                        : (item['types'] as List)
                              .map((t) => t == 'PIN_LIMIT' ? '고정 개수' : '보관 용량')
                              .join(' · '),
                  ),
                ),
              TextButton(
                onPressed: widget.outbox.working
                    ? null
                    : widget.outbox.ready
                    ? widget.outbox.flush
                    : widget.outbox.initialize,
                child: Text(
                  widget.outbox.ready ? '대기 요청 다시 전송' : '기기 요청 기록 다시 읽기',
                ),
              ),
              const Text('새 제출은 새 요청으로 저장합니다. 통신 재시도는 기존 번호를 유지합니다.'),
              if (error != null) Text(error!),
              TextButton(
                onPressed: reading ? null : reload,
                child: const Text('최근 90일 접수 이력 새로고침'),
              ),
              if (history case final rows?)
                for (final row in rows)
                  ListTile(
                    title: Text(
                      (row['types'] as List)
                          .map((t) => t == 'PIN_LIMIT' ? '고정 개수' : '보관 용량')
                          .join(' · '),
                    ),
                    subtitle: Text('${row['received_at']} · 접수됨'),
                  ),
            ],
          ),
        ),
      );
    },
  );
}
