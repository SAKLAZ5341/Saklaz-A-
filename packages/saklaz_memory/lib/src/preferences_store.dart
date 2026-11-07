/// Kullanıcı tercihleri (anahtar -> metin). Şifreli veritabanında tutulur.
abstract interface class PreferencesStore {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String? value);
}
