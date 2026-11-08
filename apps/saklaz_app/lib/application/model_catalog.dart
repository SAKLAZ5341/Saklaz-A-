import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';

/// İndirilebilir yerel modeller. Hepsi Apache-2.0 lisanslı, Hugging Face'te
/// kayıt/onay gerektirmez. Adresler sabit bir commit'e bağlıdır; SHA-256 değerleri
/// Hugging Face LFS kayıtlarıyla karşılaştırılarak doğrulanmıştır (2026-11-08).
///
/// Gemma 3 1B bu listede YOK: Google Gemma lisans onayı ve Hugging Face girişi
/// gerektirdiği için uygulama içinden doğrudan indirilemez.
const modelCatalog = <ModelSpec>[
  ModelSpec(
    id: 'qwen3-1.7b-int4',
    name: 'Qwen3 1.7B (önerilen)',
    description: 'En iyi Türkçe kalite/hız dengesi. 8 GB+ RAM önerilir. Galaxy Z Fold 7 için önerilir.',
    url: 'https://huggingface.co/litert-community/Qwen3-1.7B/resolve/e3496c7708baf1efe5482c6069a1f94695469ebc/Qwen3-1.7B_dynamic_wi4b32_afp32.litertlm',
    fileName: 'Qwen3-1.7B_dynamic_wi4b32_afp32.litertlm',
    sha256: '2a72330b504a6596d53a2c00923c57173b10f1b83e6a541213ffec08d1fc5de8',
    sizeBytes: 977184032,
    license: 'Apache-2.0',
    licenseUrl: 'https://huggingface.co/litert-community/Qwen3-1.7B',
    minRamMb: 6000,
    recommended: true,
  ),
  ModelSpec(
    id: 'qwen3-0.6b-int4',
    name: 'Qwen3 0.6B (hafif)',
    description: 'Daha hızlı ve küçük; yanıt kalitesi daha düşük. Düşük RAM\'li cihazlar için.',
    url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/bd47201734a34f1eba8ed7d28289225b60152e9e/Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
    fileName: 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
    sha256: 'bf1aba9ce8d963124407353c6aa4cbf72eba78db21ae133de983eac672ce83e0',
    sizeBytes: 343490560,
    license: 'Apache-2.0',
    licenseUrl: 'https://huggingface.co/litert-community/Qwen3-0.6B',
    minRamMb: 3000,
  ),
  ModelSpec(
    id: 'qwen2.5-1.5b-q8',
    name: 'Qwen2.5 1.5B Instruct (q8)',
    description: 'Talimat takibi güçlü, daha büyük dosya (8-bit). 8 GB+ RAM önerilir.',
    url: 'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/2f23bacf8ec78b83dfcd7271c5cb25777b1be5e0/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    fileName: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    sha256: 'c4a9b7289365ab80fe599b844b77ad253eb3c53fb0e5d963d699146a6f01255e',
    sizeBytes: 1597922856,
    license: 'Apache-2.0',
    licenseUrl: 'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct',
    minRamMb: 6000,
  ),
];

ModelSpec? modelById(String? id) {
  for (final m in modelCatalog) {
    if (m.id == id) return m;
  }
  return null;
}
