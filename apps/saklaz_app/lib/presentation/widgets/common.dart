import 'package:flutter/material.dart';

import '../theme/saklaz_theme.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(color: SaklazColors.cyan, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700),
        ),
      );
}

/// Ekran içeriğini açık Fold 7 ekranında okunabilir genişlikte tutar.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 760});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

Future<bool> confirmDialog(BuildContext context, String title, String body, {String action = 'Onayla', bool destructive = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: SaklazColors.danger) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Metin diyaloğu. Denetleyici diyaloğun kendi yaşam döngüsünde imha edilir
/// (kapanış animasyonu sırasında "disposed controller" hatası olmaması için).
Future<String?> textDialog(BuildContext context, String title, {String initial = '', String hint = '', int maxLength = 500}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, hint: hint, maxLength: maxLength),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.hint, required this.maxLength});
  final String title;
  final String initial;
  final String hint;
  final int maxLength;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: widget.maxLength,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(hintText: widget.hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text.trim()), child: const Text('Kaydet')),
        ],
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.label, required this.color, this.onTap, this.tooltip});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}
