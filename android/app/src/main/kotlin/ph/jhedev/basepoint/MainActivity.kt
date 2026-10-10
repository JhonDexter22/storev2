package ph.jhedev.basepoint

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tones: ToneGenerator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12+ draws its own splash and, left alone, fades it out in two
        // steps (the mark, then the blue). The first Flutter frame is the same
        // picture and its intro carries on from it, so the fade only showed as
        // the mark blinking out and back. Take the splash away at once instead.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The scanner's beep. A tone rather than the system click, which only
        // plays when the phone's "touch sounds" setting is on — and on most
        // phones it is not, so the scan sound switch would have done nothing.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ph.jhedev.basepoint/beep")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "beep" -> result.success(beep(call.argument<Boolean>("ok") ?: true))
                    else -> result.notImplemented()
                }
            }
    }

    /** A short high beep for a code that was found, a low one for one that was not. */
    private fun beep(ok: Boolean): Boolean = try {
        val generator = tones ?: ToneGenerator(AudioManager.STREAM_MUSIC, 90).also { tones = it }
        if (ok) {
            generator.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
        } else {
            generator.startTone(ToneGenerator.TONE_PROP_NACK, 250)
        }
    } catch (e: RuntimeException) {
        // No audio hardware free (a call in progress, say): the scan still
        // counts, it is just silent.
        false
    }

    override fun onDestroy() {
        tones?.release()
        tones = null
        super.onDestroy()
    }
}
