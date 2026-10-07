import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/database/local_models.dart';
import '../../core/sync/canonical_conflict_plan.dart';
import '../../core/sync/conflict_resolution_plan.dart';
import '../../core/sync/conflict_review.dart';
import '../../core/theme/app_tokens.dart';

class ConflictScreen extends StatefulWidget {
  const ConflictScreen({required this.actions, required this.opId, super.key});
  final ConflictActions actions;
  final String opId;
  @override
  State<ConflictScreen> createState() => _ConflictScreenState();
}

class _ConflictScreenState extends State<ConflictScreen> {
  ConflictReview? _review;
  String? _message;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _review = null;
    });
    try {
      final review = await widget.actions.review(widget.opId);
      if (review.comparison.conflicts.any((g) => g.contains('tag_ids'))) {
        for (final values in [review.local, review.server]) {
          final ids = values['tag_ids'];
          if (ids is! List ||
              ids.any(
                (id) => id is! String || review.tagName(id, values) == null,
              )) {
            throw StateError('Tag names are required for this choice');
          }
        }
      }
      if (mounted) setState(() => _review = review);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = '현재 이 변경을 선택할 수 없어요. 입력은 보존돼요. 상태를 다시 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(ConflictChoice choice) async {
    final review = _review;
    if (_busy || review == null) return;
    setState(() => _busy = true);
    try {
      await widget.actions.resolve(review, {
        for (final group in review.comparison.conflicts)
          for (final field in group) field: choice,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _review = null;
          _message = '정보가 바뀌었거나 저장하지 못했어요. 입력은 보존돼요. 다시 확인한 뒤 선택해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _labels = {
    'title': '곡 제목',
    'artist': '아티스트',
    'title_snapshot': '녹음 제목',
    'artist_snapshot': '아티스트',
    'version_code': '버전',
    'tier': '티어',
    'note': '메모',
    'name': '태그 이름',
    'representative_key_mode': '대표 키',
    'representative_key_shift': '대표 키 이동',
    'key_mode': '키',
    'key_shift': '키 이동',
    'recorded_at': '녹음 시각',
    'timezone_id': '시간대',
    'timezone_offset_minutes': '시간 차이(분)',
    'condition_code': '컨디션',
    'tag_ids': '태그',
  };
  String _value(String field, Object? value, Map<String, dynamic> values) {
    if (value == null) return '없음';
    if (value == '') return '비어 있음';
    if (field == 'tag_ids' && value is List) {
      return value.isEmpty
          ? '없음'
          : value
                .map((id) => _review!.tagName(id as String, values)!)
                .join(', ');
    }
    if (field.endsWith('key_mode')) {
      return const {
            'ORIGINAL': '원키',
            'MALE': '남성 키',
            'FEMALE': '여성 키',
          }[value] ??
          value.toString();
    }
    if (field == 'condition_code') {
      return const {
            'VERY_GOOD': '매우 좋음',
            'GOOD': '좋음',
            'NORMAL': '보통',
        'BAD': '안 좋음',
          }[value] ??
          value.toString();
    }
    return value.toString();
  }

  Widget _side(
    String title,
    Map<String, dynamic> values,
    Set<String> fields,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      for (final field in fields)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            '${_labels[field] ?? '변경 항목'}: ${_value(field, values[field], values)}',
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final review = _review;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('동기화 충돌')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_message != null) ...[
                Text(_message!),
                OutlinedButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('다시 확인'),
                ),
              ],
              if (review != null) ...[
                if (review.pendingReview)
                  const Text('자동 전송을 보류한 입력이에요. 최신 서버 값과 비교해 다시 선택해 주세요.'),
                Text(
                  review.comparison.requiresChoice
                      ? '같은 항목이 다르게 수정됐어요'
                      : '서로 다른 항목이 수정됐어요',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                if (review.localJson != null &&
                    canonicalJson(jsonDecode(review.localJson!) as Map<String, dynamic>) !=
                        canonicalJson(review.local))
                  const Text('이 충돌 이후 저장된 초안은 별도로 보존돼요. 아래 선택은 충돌한 요청의 입력에 적용돼요.'),
                Text(
                  review.comparison.requiresChoice
                      ? '아래 두 입력을 확인하고 사용할 쪽을 선택해 주세요. 충돌하지 않은 변경은 함께 유지돼요.'
                      : '충돌하지 않은 변경을 서버 정보에 다시 적용할 수 있어요.',
                ),
                for (final group in review.comparison.conflicts)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _side('서버 값', review.server, group),
                          const Divider(),
                          _side('이 기기 입력', review.local, group),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                if (review.comparison.requiresChoice) ...[
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _choose(ConflictChoice.server),
                    child: const Text('서버 값 사용'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _choose(ConflictChoice.local),
                    child: const Text('이 기기 입력 사용'),
                  ),
                ] else
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _choose(ConflictChoice.local),
                    child: const Text('안전한 변경 다시 적용'),
                  ),
                const Text('선택은 이 기기에 저장돼요. 서버 전송 결과는 동기화 상태에서 확인할 수 있어요.'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CanonicalConflictScreen extends StatefulWidget {
  const CanonicalConflictScreen({required this.actions, required this.intentId, super.key});
  final CanonicalConflictActions actions;
  final String intentId;
  @override
  State<CanonicalConflictScreen> createState() => _CanonicalConflictScreenState();
}

class _CanonicalConflictScreenState extends State<CanonicalConflictScreen> {
  CanonicalConflictReview? _review;
  bool _busy = false;
  String? _message;
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; _review = null; });
    try {
      final value = await widget.actions.reviewCanonical(widget.intentId);
      if (mounted) setState(() => _review = value);
    } catch (_) {
      if (mounted) setState(() => _message = '정보를 확인하지 못했어요. 입력은 보존돼요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(ConflictChoice choice) async {
    final review = _review;
    if (_busy || review == null || !review.canChoose) return;
    setState(() => _busy = true);
    try {
      await widget.actions.resolveCanonical(review, choice);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _review = null;
          _message = '정보가 바뀌었거나 저장하지 못했어요. 다시 확인한 뒤 선택해 주세요. 입력은 보존돼요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('같은 곡의 개인 편집')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Text(_message!),
        if (review?.blockedReason != null) Text(review!.blockedReason!),
        if (review != null && review.canChoose) ...[
          const Text('같은 곡으로 연결되기 전의 입력이에요. 서로 다른 곡의 값을 자동으로 합치지 않아요. 사용할 쪽을 선택해 주세요.'),
          if (review.latestDraft case final Map<String, dynamic> draft)
            if (canonicalSongFields.any((key) => draft[key] != review.server[key] && draft[key] != review.candidate[key]))
              Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('별도로 보존되는 최신 초안'),
                  for (final key in canonicalSongFields)
                    if (draft[key] != review.server[key])
                      Text('${_ConflictScreenState._labels[key]}: ${draft[key] ?? '없음'}'),
                ],
              ))),
          for (final field in review.candidate.keys)
            Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_ConflictScreenState._labels[field] ?? '변경 항목'),
                Text('서버 값: ${review.server[field] ?? '없음'}'),
                Text('이 기기 입력: ${review.candidate[field] ?? '없음'}'),
              ],
            ))),
          FilledButton(onPressed: _busy ? null : () => _choose(ConflictChoice.server), child: const Text('서버 값 사용')),
          OutlinedButton(onPressed: _busy ? null : () => _choose(ConflictChoice.local), child: const Text('이 기기 입력 사용')),
          const Text('선택 후에도 서버 전송이 필요한 변경은 대기 상태로 남아요. 이후에 저장한 초안과 원본 입력은 보존돼요.'),
        ],
        OutlinedButton(onPressed: _busy ? null : _load, child: const Text('다시 확인')),
      ])),
    ));
  }
}
