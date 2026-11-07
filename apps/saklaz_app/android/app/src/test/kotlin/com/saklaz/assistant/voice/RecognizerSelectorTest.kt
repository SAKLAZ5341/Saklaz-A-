package com.saklaz.assistant.voice

import com.saklaz.assistant.voice.RecognizerSelector.Candidate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RecognizerSelectorTest {

    private val own = "com.saklaz.assistant"

    @Test
    fun `kendi vekil servisimizi asla secmez`() {
        val result = RecognizerSelector.choose(listOf(Candidate(own, "$own.assist.SaklazRecognitionService")), own)
        assertNull(result)
    }

    @Test
    fun `Google cihaz ici zekayi Samsung'a tercih eder`() {
        val result = RecognizerSelector.choose(
            listOf(
                Candidate(own, "x"),
                Candidate("com.samsung.android.bixby.agent", "s"),
                Candidate("com.google.android.as", "g"),
            ),
            own,
        )
        assertEquals("com.google.android.as", result?.packageName)
    }

    @Test
    fun `tercih listesinde yoksa ilk diger servisi secer`() {
        val result = RecognizerSelector.choose(
            listOf(Candidate(own, "x"), Candidate("com.vendor.asr", "v")),
            own,
        )
        assertEquals("com.vendor.asr", result?.packageName)
    }
}
