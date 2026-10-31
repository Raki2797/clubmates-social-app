package com.clubmates.app.data.network

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.text.SimpleDateFormat
import java.util.*

// Handles both "2025-05-20T20:28:00Z" and "2025-05-20T20:28:00.000Z"
object FlexibleDateSerializer : KSerializer<Date> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("FlexibleDate", PrimitiveKind.STRING)

    private val formatters = listOf(
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") },
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") },
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US),
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US),
    )

    override fun serialize(encoder: Encoder, value: Date) {
        encoder.encodeString(formatters[0].format(value))
    }

    override fun deserialize(decoder: Decoder): Date {
        val raw = decoder.decodeString()
        for (fmt in formatters) {
            try { return fmt.parse(raw)!! } catch (_: Exception) {}
        }
        return Date(0)
    }
}
