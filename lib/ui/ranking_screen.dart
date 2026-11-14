import 'package:flutter/material.dart';

import '../rankings/ranking.dart';

/// 順位表画面（Issue #48）。
///
/// 今月 / 歴代の切り替えと、組織（学域コード）フィルタに対応する。
/// データが無い・取得できない場合はその旨を表示する。
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key, required this.repository});

  final RankingRepository repository;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  String _period = 'current';
  String? _organizationCode;
  List<RankingEntry> _entries = const <RankingEntry>[];
  List<String> _organizations = const <String>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.repository.fetch(
        period: _period,
        organizationCode: _organizationCode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        // フィルタ候補は読み込み済みデータの組織コードから作る
        final orgs = entries.map((e) => e.organizationCode).toSet().toList()
          ..sort();
        if (orgs.isNotEmpty) {
          _organizations = orgs;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = const <RankingEntry>[];
        _error = '順位表を取得できませんでした。';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('順位表'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'current', label: Text('今月')),
                      ButtonSegment(value: 'all', label: Text('歴代')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _period = selection.first;
                      });
                      _load();
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _organizationCode,
                      hint: const Text('組織フィルタ'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('すべての組織'),
                        ),
                        ..._organizations.map(
                          (org) => DropdownMenuItem<String?>(
                            value: org,
                            child: Text(org),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _organizationCode = value;
                        });
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('この期間の記録はまだありません。'));
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return ListTile(
          leading: CircleAvatar(child: Text('${entry.rank}')),
          title: Text(entry.nickname),
          subtitle: Text(
            '${entry.organizationCode} ・ ${entry.termIdentifier}',
          ),
          trailing: Text(
            '${entry.totalSeconds.toStringAsFixed(1)} 秒'
            '${entry.rankGrade != null ? ' ・ ${entry.rankGrade}' : ''}',
          ),
        );
      },
    );
  }
}
