import 'package:flutter/material.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_core/saklaz_core.dart';

import '../theme/saklaz_theme.dart';

/// Konuşma geçmişi (en yeni altta) + bekleyen onay kartı.
class ConversationView extends StatefulWidget {
  const ConversationView({
    super.key,
    required this.messages,
    this.partialText = '',
    this.pending,
    this.busy = false,
    required this.onReplay,
    required this.onResolve,
  });

  final List<ChatMessage> messages;
  final String partialText;
  final PendingAction? pending;
  final bool busy;
  final void Function(ChatMessage m) onReplay;
  final void Function({required bool accept, bool preferLocal}) onResolve;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ConversationView old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length ||
        old.partialText != widget.partialText ||
        old.pending != widget.pending ||
        old.busy != widget.busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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
    final extras = <Widget>[
      if (widget.partialText.isNotEmpty) _Bubble.pending(widget.partialText),
      if (widget.busy) const _Thinking(),
      if (widget.pending != null) _PendingCard(action: widget.pending!, onResolve: widget.onResolve),
    ];
    if (items.isEmpty && extras.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Merhaba! Benimle yazarak veya "Konuşmayı Başlat" ile sesli konuşabilirsin.\n'
            'Kendinden bahset; seni zamanla tanıyacağım.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SaklazColors.textSecondary, height: 1.5),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length + extras.length,
      itemBuilder: (context, i) {
        if (i >= items.length) return extras[i - items.length];
        final m = items[i];
        if (m.role == ChatRole.system) return _LearnedChip(text: m.text);
        return _Bubble(message: m, onReplay: m.isUser ? null : () => widget.onReplay(m));
      },
    );
  }
}

class _LearnedChip extends StatelessWidget {
  const _LearnedChip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SaklazColors.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SaklazColors.cyan.withValues(alpha: 0.3)),
          ),
          child: Text(text, style: const TextStyle(color: SaklazColors.cyan, fontSize: 12.5)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onReplay}) : pendingText = null;
  const _Bubble.pending(String text)
      : pendingText = text,
        message = null,
        onReplay = null;

  final ChatMessage? message;
  final String? pendingText;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    final pending = pendingText != null;
    final isUser = pending || message!.isUser;
    final text = pendingText ?? message!.text;
    final maxW = MediaQuery.sizeOf(context).width * 0.8;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW.clamp(200, 600)),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
        decoration: BoxDecoration(
          color: isUser ? SaklazColors.violet.withValues(alpha: pending ? 0.12 : 0.24) : SaklazColors.surfaceHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 20),
          ),
          border: Border.all(color: isUser ? SaklazColors.violet.withValues(alpha: 0.4) : SaklazColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SelectableText(
                text,
                style: TextStyle(
                  height: 1.4,
                  fontStyle: pending ? FontStyle.italic : FontStyle.normal,
                  color: pending ? SaklazColors.textSecondary : SaklazColors.textPrimary,
                ),
              ),
            ),
            if (!isUser && message != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                SourceBadge(source: message!.source),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Tekrar dinle',
                  iconSize: 18,
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay_rounded),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Yanıtın kaynağını gösterir (şeffaflık: yerel mi, bulut mu?).
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});
  final MessageSource source;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (source) {
      MessageSource.localRules => ('Yerel', SaklazColors.listening, Icons.phone_android),
      MessageSource.memory => ('Hafıza', SaklazColors.cyan, Icons.memory),
      MessageSource.localLlm => ('Yerel AI', SaklazColors.listening, Icons.psychology),
      MessageSource.cloud => ('Bulut', SaklazColors.magenta, Icons.cloud_outlined),
      MessageSource.system => ('Sistem', SaklazColors.textSecondary, Icons.info_outline),
      MessageSource.user => ('Sen', SaklazColors.textSecondary, Icons.person),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();
  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('SAKLAZ düşünüyor…', style: TextStyle(color: SaklazColors.textSecondary)),
          ]),
        ),
      );
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.action, required this.onResolve});
  final PendingAction action;
  final void Function({required bool accept, bool preferLocal}) onResolve;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail, accept, reject) = switch (action) {
      ConfirmRemember(:final content) => (
          Icons.bookmark_add_outlined,
          'Hafızaya kaydedilsin mi?',
          '"$content"\nYalnızca bu cihazda, şifreli saklanır.',
          'Kaydet',
          'Vazgeç',
        ),
      ConfirmCloud(:final webSearch) => (
          Icons.cloud_upload_outlined,
          'Bulut sağlayıcısına gönderilsin mi?',
          'Gönderilecek: bu mesaj ve son birkaç konuşma mesajı. Kişisel hafızan ayarlarda izin vermedikçe gönderilmez. '
              'Ücret sağlayıcıya göre sana aittir.${webSearch ? '\nWeb araması kullanılabilir (ek maliyet).' : ''}',
          'Gönder',
          'Gönderme',
        ),
      ConfirmAgentAction(action: final a) => (
          switch (a) {
            WhatsAppAction() => Icons.chat_outlined,
            CallAction() => Icons.call_outlined,
            CreateReminderAction() => Icons.alarm_add_outlined,
            SetAlarmAction() => Icons.alarm,
            AddCalendarEventAction() => Icons.event_outlined,
            SaveNoteAction() => Icons.note_add_outlined,
            ReplyNotificationAction() => Icons.reply,
          },
          a.risk == RiskLevel.high ? 'Onay gerekli (yalnızca ekrandan)' : 'Onaylıyor musun?',
          a.risk == RiskLevel.high ? a.preview : '${a.preview}\nSesli "evet" veya "hayır" da diyebilirsin.',
          'Onayla',
          'İptal',
        ),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: SaklazColors.warning)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: SaklazColors.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            Text(detail, style: const TextStyle(color: SaklazColors.textSecondary, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(onPressed: () => onResolve(accept: true), child: Text(accept)),
              if (action case ConfirmCloud(localAlternative: true))
                OutlinedButton(onPressed: () => onResolve(accept: false, preferLocal: true), child: const Text('Yerelde yanıtla')),
              TextButton(onPressed: () => onResolve(accept: false), child: Text(reject)),
            ]),
          ],
        ),
      ),
    );
  }
}
