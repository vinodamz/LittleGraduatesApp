package `in`.thelittlegraduates.little_graduates

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.exifinterface.media.ExifInterface
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/// Photo and video compression for the materials outbox. File bytes themselves
/// upload from Dart (WorkManager). This channel only exists on the UI engine.
@OptIn(UnstableApi::class)
class MaterialsBridge(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "videoInfo" -> videoInfo(call.argument<String>("path"), result)
            "transcodeVideo" -> transcode(
                call.argument<String>("source"),
                call.argument<String>("dest"),
                result,
            )
            "compressImage" -> compressImage(
                call.argument<String>("source"),
                call.argument<String>("dest"),
                call.argument<Int>("maxEdge") ?: 1600,
                call.argument<Int>("quality") ?: 75,
                result,
            )
            "enqueueUpload" -> result.success(null)
            "takeUploadResults" -> result.success(emptyList<Map<String, Any?>>())
            "inFlightUploads" -> result.success(emptyList<String>())
            else -> result.notImplemented()
        }
    }

    private fun videoInfo(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.error("video", "Missing video.", null)
            return
        }
        Thread {
            try {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(path)
                val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                retriever.release()
                val swapped = rotation == 90 || rotation == 270
                val payload = mapOf(
                    "width" to if (swapped) height else width,
                    "height" to if (swapped) width else height,
                )
                main { result.success(payload) }
            } catch (e: Exception) {
                main { result.error("video", e.message, null) }
            }
        }.start()
    }

    private fun transcode(source: String?, dest: String?, result: MethodChannel.Result) {
        if (source.isNullOrEmpty() || dest.isNullOrEmpty()) {
            result.error("transcode", "Missing video.", null)
            return
        }
        val destFile = File(dest)
        if (destFile.exists()) destFile.delete()
        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(source))))
            .setEffects(Effects(emptyList(), listOf(Presentation.createForHeight(720))))
            .build()
        val transformer = Transformer.Builder(activity.applicationContext)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    result.success(null)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    result.error("transcode", exportException.message, null)
                }
            })
            .build()
        try {
            transformer.start(item, dest)
        } catch (e: Exception) {
            result.error("transcode", e.message, null)
        }
    }

    private fun compressImage(
        source: String?,
        dest: String?,
        maxEdge: Int,
        quality: Int,
        result: MethodChannel.Result,
    ) {
        if (source.isNullOrEmpty() || dest.isNullOrEmpty()) {
            result.error("compress", "Missing photo.", null)
            return
        }
        Thread {
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(source, bounds)
                var sample = 1
                while (bounds.outWidth / sample > maxEdge * 2 || bounds.outHeight / sample > maxEdge * 2) {
                    sample *= 2
                }
                val decoded = BitmapFactory.decodeFile(source, BitmapFactory.Options().apply { inSampleSize = sample })
                    ?: throw IllegalArgumentException("Could not read the photo.")
                val oriented = applyExif(decoded, source)
                val longEdge = max(oriented.width, oriented.height)
                val scaled = if (longEdge > maxEdge) {
                    val scale = maxEdge.toFloat() / longEdge
                    Bitmap.createScaledBitmap(
                        oriented,
                        (oriented.width * scale).roundToInt().coerceAtLeast(1),
                        (oriented.height * scale).roundToInt().coerceAtLeast(1),
                        true,
                    )
                } else {
                    oriented
                }
                FileOutputStream(File(dest)).use { out ->
                    if (!scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(70, 80), out)) {
                        throw IllegalStateException("Could not write the photo.")
                    }
                }
                main { result.success(null) }
            } catch (e: Exception) {
                main { result.error("compress", e.message, null) }
            }
        }.start()
    }

    private fun applyExif(bitmap: Bitmap, path: String): Bitmap {
        val orientation = ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.preScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.preScale(-1f, 1f)
            }
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun main(block: () -> Unit) {
        Handler(Looper.getMainLooper()).post(block)
    }

    companion object {
        const val CHANNEL = "in.thelittlegraduates.app/materials_upload"
    }
}
