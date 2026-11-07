package com.saklaz.assistant.assist

import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

/** Asistan her çağrıldığında sistem bu servisten yeni bir oturum ister. */
class SaklazSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = SaklazSession(this)
}
