import 'package:flutter/material.dart';

/// ネーム入力画面（Issue #47）。
///
/// - ニックネームは任意入力。未入力の場合は呼び出し側で「名称未設定」にする
/// - 組織表示名は端末設定の表示専用で、この画面では変更できない
class NameEntryScreen extends StatefulWidget {
  const NameEntryScreen({
    super.key,
    required this.organizationDisplayName,
    required this.totalSeconds,
  });

  final String organizationDisplayName;
  final double totalSeconds;

  @override
  State<NameEntryScreen> createState() => _NameEntryScreenState();
}

class _NameEntryScreenState extends State<NameEntryScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('記録の登録')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'タイム ${widget.totalSeconds.toStringAsFixed(1)} 秒',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'ニックネーム（任意）',
                hintText: '未入力の場合は「名称未設定」で登録されます',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '組織（端末設定・変更不可）',
                border: OutlineInputBorder(),
              ),
              child: Text(widget.organizationDisplayName),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(_controller.text.trim());
              },
              child: const Text('この内容で登録する'),
            ),
          ],
        ),
      ),
    );
  }
}
