import 'local_intent_engine.dart';

/// Bulut zekâsı kullanım izni (kullanıcı ayarı).
enum CloudMode {
  /// Asla buluta gönderme.
  off,

  /// Her bulut isteğinden önce kullanıcıya sor (varsayılan).
  ask,

  /// Gerektiğinde sormadan buluta gönder.
  always,
}

enum Brain { localRules, memory, localLlm, cloud }

enum UnavailableReason { offline, cloudNotConfigured, cloudDisabled, noLocalModel }

sealed class RouteDecision {
  const RouteDecision();
}

class UseBrain extends RouteDecision {
  const UseBrain(this.brain);
  final Brain brain;
}

/// Buluta göndermeden önce kullanıcı izni gerekli.
class AskCloudConsent extends RouteDecision {
  const AskCloudConsent({required this.localAlternative});

  /// Kullanıcı reddederse yerel model ile denenebilir mi?
  final bool localAlternative;
}

class Unavailable extends RouteDecision {
  const Unavailable(this.reason);
  final UnavailableReason reason;
}

class RouteContext {
  const RouteContext({
    required this.cloudMode,
    required this.cloudConfigured,
    required this.online,
    required this.localLlmReady,
  });

  final CloudMode cloudMode;
  final bool cloudConfigured;
  final bool online;
  final bool localLlmReady;

  bool get cloudUsable => cloudMode != CloudMode.off && cloudConfigured && online;

  UnavailableReason get cloudBlocker {
    if (cloudMode == CloudMode.off) return UnavailableReason.cloudDisabled;
    if (!cloudConfigured) return UnavailableReason.cloudNotConfigured;
    return UnavailableReason.offline;
  }
}

/// Akıllı model seçimi:
///  * Basit komutlar -> yerel kurallar
///  * Kişisel hafıza -> yerel hafıza
///  * Güncel bilgi -> bulut (bağlantı + izin varsa)
///  * Karmaşık analiz -> bulut (izinle), yoksa yerel model
///  * Diğer genel sorular -> önce yerel model, yoksa bulut (izinle)
///  * İnternet yoksa yerel özellikler çalışmaya devam eder
class AssistantRouter {
  const AssistantRouter();

  RouteDecision decide(LocalIntent intent, RouteContext c) {
    switch (intent) {
      case GreetingIntent() || TimeIntent() || DateIntent() || IdentityIntent() || ThanksIntent() || HelpIntent():
        return const UseBrain(Brain.localRules);
      case RememberIntent() || MemoryQueryIntent():
        return const UseBrain(Brain.memory);
      case GeneralIntent(:final needsInternet, :final complex):
        if (needsInternet) {
          return c.cloudUsable ? _cloud(c, localAlternative: false) : Unavailable(c.cloudBlocker);
        }
        if (complex) {
          if (c.cloudUsable) return _cloud(c, localAlternative: c.localLlmReady);
          if (c.localLlmReady) return const UseBrain(Brain.localLlm);
          return Unavailable(c.cloudBlocker);
        }
        if (c.localLlmReady) return const UseBrain(Brain.localLlm);
        if (c.cloudUsable) return _cloud(c, localAlternative: false);
        return Unavailable(c.cloudMode == CloudMode.off || !c.cloudConfigured
            ? UnavailableReason.noLocalModel
            : c.cloudBlocker);
    }
  }

  RouteDecision _cloud(RouteContext c, {required bool localAlternative}) => c.cloudMode == CloudMode.always
      ? const UseBrain(Brain.cloud)
      : AskCloudConsent(localAlternative: localAlternative);
}
