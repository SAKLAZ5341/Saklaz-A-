/// Kullanıcıya gösterilebilir, kişisel veri içermeyen hata.
class Failure {
  const Failure(this.code, this.message, {this.cause});

  /// Makine tarafından okunabilir kod, ör. `mic-permission`.
  final String code;

  /// Türkçe, kullanıcıya gösterilebilir açıklama.
  final String message;

  final Object? cause;

  @override
  String toString() => 'Failure($code): $message';
}
