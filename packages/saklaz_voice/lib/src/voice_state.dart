enum VoicePhase {
  /// Mikrofon kapalı, konuşma yok.
  idle,

  /// Mikrofon izni isteniyor.
  requestingPermission,

  /// Mikrofon AÇIK (kullanıcıya görsel olarak gösterilmelidir).
  listening,

  /// Söylenen metin işleniyor.
  thinking,

  /// SAKLAZ sesli yanıt veriyor.
  speaking,
}

class VoiceState {
  const VoiceState({
    this.phase = VoicePhase.idle,
    this.level = 0,
    this.partialText = '',
    this.errorMessage,
  });

  final VoicePhase phase;

  /// 0..1 aralığında normalize edilmiş mikrofon seviyesi.
  final double level;

  final String partialText;

  /// Son hata (kullanıcıya gösterilebilir), yoksa null.
  final String? errorMessage;

  bool get micActive => phase == VoicePhase.listening;

  VoiceState copyWith({
    VoicePhase? phase,
    double? level,
    String? partialText,
    String? errorMessage,
    bool clearError = false,
  }) =>
      VoiceState(
        phase: phase ?? this.phase,
        level: level ?? this.level,
        partialText: partialText ?? this.partialText,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}
