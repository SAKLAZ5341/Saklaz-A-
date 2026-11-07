package com.saklaz.assistant.voice

/**
 * Cihazdaki tanıma servisleri arasından SAKLAZ'ın kendisi dışında en uygun olanı
 * seçer. Saf Kotlin: Android'e bağımlı değildir, birim testi yapılabilir.
 */
object RecognizerSelector {

    /** Tercih sırası: Google cihaz içi zekâ, Google uygulaması, Samsung. */
    val PREFERRED_PACKAGES = listOf(
        "com.google.android.as",
        "com.google.android.tts",
        "com.google.android.googlequicksearchbox",
        "com.samsung.android.bixby.agent",
    )

    data class Candidate(val packageName: String, val className: String)

    fun choose(candidates: List<Candidate>, ownPackage: String): Candidate? {
        val others = candidates.filter { it.packageName != ownPackage }
        if (others.isEmpty()) return null
        for (pkg in PREFERRED_PACKAGES) {
            others.firstOrNull { it.packageName == pkg }?.let { return it }
        }
        return others.first()
    }
}
