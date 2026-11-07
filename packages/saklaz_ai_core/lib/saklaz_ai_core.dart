/// SAKLAZ AI Core — iki beyinli mimari.
///
///  * Yerel: kural tabanlı niyet motoru + yerel hafıza + (varsa) cihaz içi LLM
///  * Bulut: OpenAI Responses API, YALNIZCA SAKLAZ Gateway üzerinden
///
/// [AssistantRouter] hangi beynin kullanılacağına karar verir;
/// [SaklazAssistant] kararı uygular.
library;

export 'src/assistant_engine.dart';
export 'src/gateway_client.dart';
export 'src/http_transport.dart';
export 'src/llm.dart';
export 'src/local_intent_engine.dart';
export 'src/local_llm.dart';
export 'src/router.dart';
