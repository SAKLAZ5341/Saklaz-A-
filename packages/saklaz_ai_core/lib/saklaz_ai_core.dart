/// SAKLAZ AI Core — iki beyinli mimari.
///
///  * Yerel (varsayılan): kural tabanlı niyet motoru + şifreli hafıza + LiteRT-LM yerel LLM
///  * Bulut (isteğe bağlı, varsayılan PASİF): OpenAI Responses API, DeepSeek,
///    OpenAI uyumlu özel sağlayıcı veya SAKLAZ Gateway
library;

export 'src/assistant_engine.dart';
export 'src/cloud_providers.dart';
export 'src/device_ports.dart';
export 'src/fact_extractor.dart';
export 'src/gateway_client.dart';
export 'src/http_transport.dart';
export 'src/llm.dart';
export 'src/local_intent_engine.dart';
export 'src/local_llm.dart';
export 'src/router.dart';
export 'src/turkish_time.dart';
