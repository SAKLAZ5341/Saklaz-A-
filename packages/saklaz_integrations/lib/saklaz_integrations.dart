/// SAKLAZ entegrasyonları. Phase 1: yalnızca arayüz ve planlanan modüllerin
/// listesi. Hiçbir entegrasyon henüz uygulanmadı (Phase 5).
library;

enum IntegrationStatus { planned, available, connected, error }

abstract interface class IntegrationModule {
  String get id;
  String get displayName;
  String get description;
  IntegrationStatus get status;
}

class PlannedIntegration implements IntegrationModule {
  const PlannedIntegration(this.id, this.displayName, this.description);

  @override
  final String id;
  @override
  final String displayName;
  @override
  final String description;
  @override
  IntegrationStatus get status => IntegrationStatus.planned;
}

const plannedIntegrations = <IntegrationModule>[
  PlannedIntegration('gmail', 'Gmail', 'E-posta okuma ve onaylı gönderim'),
  PlannedIntegration('calendar', 'Google Takvim', 'Etkinlik listeleme ve ekleme'),
  PlannedIntegration('whatsapp', 'WhatsApp', 'Mesaj taslağı ve bildirimden onaylı yanıt'),
  PlannedIntegration('camera', 'Kamera ve Belgeler', 'Fotoğraf ve belge analizi'),
];
