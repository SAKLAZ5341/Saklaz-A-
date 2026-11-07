import 'package:flutter/material.dart';
import 'package:saklaz_core/saklaz_core.dart';

import '../theme/saklaz_theme.dart';

/// Konuşma geçmişi (en yeni altta).
class ConversationView extends StatefulWidget {
  const ConversationView({super.key, required this.messages, this.partialText = ''});

  final List<ChatMessage> messages;

  /// Dinlerken anlık (henüz kesinleşmemiş) metin.
  final String partialText;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ConversationView old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length || old.partialText != widget.partialText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.messages;
    final showPartial = widget.partialText.isNotEmpty;
    if (items.isEmpty && !showPartial) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Henüz konuşma yok.\nMikrofona dokun veya yaz.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SaklazColors.textSecondary, height: 1.5),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length + (showPartial ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == items.length) {
          return _Bubble(text: widget.partialText, isUser: true, pending: true);
        }
        final m = items[i];
        return _Bubble(text: m.text, isUser: m.isUser);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser, this.pending = false});
  final String text;
  final bool isUser;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW.clamp(200, 560)),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? SaklazColors.violet.withValues(alpha: pending ? 0.12 : 0.24) : SaklazColors.surfaceHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 20),
          ),
          border: Border.all(
            color: isUser ? SaklazColors.violet.withValues(alpha: 0.4) : SaklazColors.outline,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            height: 1.4,
            fontStyle: pending ? FontStyle.italic : FontStyle.normal,
            color: pending ? SaklazColors.textSecondary : SaklazColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
