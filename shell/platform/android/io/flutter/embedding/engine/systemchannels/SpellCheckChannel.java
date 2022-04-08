package io.flutter.embedding.engine.systemchannels;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.Log;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.JSONMethodCodec;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import org.json.JSONArray;
import org.json.JSONException;

/**
 * {@link SpellCheckChannel} is a platform channel that is used by Flutter to initiate spell check
 * in the Android engine and for the Android engine to send back the results.
 *
 * <p>When there is new text to be spell checked, Flutter will send to the Android engine the
 * message {@code SpellCheck.initiateSpellCheck} with the {@code String} locale to spell check with
 * and the {@code String} of text to spell check as arguments. In response, the {@link
 * io.flutter.plugin.editing.SpellCheckPlugin} will make a call to Android's spell check service to
 * fetch spell check results for the specified text.
 *
 * <p>Once the spell check results are received by the {@link
 * io.flutter.plugin.editing.SpellCheckPlugin}, it will send to Flutter the message {@code
 * SpellCheck.updateSpellCheckResults} with the {@code ArrayList<String>} of encoded spell check
 * results (see {@link
 * io.flutter.plugin.editing.SpellCheckPlugin#onGetSentenceSuggestions(SentenceSuggestionsInfo[])}
 * for details) as an argument.
 *
 * <p>{@link io.flutter.plugin.editing.SpellCheckPlugin} implements {@link SpellCheckMethodHandler}
 * to initiate spell check. Implement {@link SpellCheckMethodHandler} to respond to Flutter spell
 * check messages.
 */
public class SpellCheckChannel {
  private static final String TAG = "SpellCheckChannel";

  public final MethodChannel channel;
  private SpellCheckMethodHandler spellCheckMethodHandler;

  @NonNull
  final MethodChannel.MethodCallHandler parsingMethodHandler =
      new MethodChannel.MethodCallHandler() {
        @Override
        public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
          if (spellCheckMethodHandler == null) {
            // If no explicit SpellCheckMethodHandler has been registered then we don't
            // need to forward this call to an API. Return.
            Log.v(
                TAG,
                "No SpellCheckeMethodHandler registered, call not forwarded to spell check API.");
            return;
          }
          String method = call.method;
          Object args = call.arguments;
          Log.v(TAG, "Received '" + method + "' message.");
          switch (method) {
            case "SpellCheck.initiateSpellCheck":
              try {
                final JSONArray argumentList = (JSONArray) args;
                String locale = argumentList.getString(0);
                String text = argumentList.getString(1);
                spellCheckMethodHandler.initiateSpellCheck(locale, text);
                result.success(null);
              } catch (JSONException exception) {
                result.error("error", exception.getMessage(), null);
              }
              break;
            default:
              result.notImplemented();
              break;
          }
        }
      };

  public SpellCheckChannel(@NonNull DartExecutor dartExecutor) {
    channel = new MethodChannel(dartExecutor, "flutter/spellcheck", JSONMethodCodec.INSTANCE);
    channel.setMethodCallHandler(parsingMethodHandler);
  }

  /** Responsible for sending spell check results through this channel. */
  public void updateSpellCheckResults(ArrayList<String> spellCheckResults) {
    channel.invokeMethod("SpellCheck.updateSpellCheckResults", spellCheckResults);
  }

  /**
   * Sets the {@link SpellCheckMethodHandler} which receives all requests to spell check the
   * specified text sent through this channel.
   */
  public void setSpellCheckMethodHandler(
      @Nullable SpellCheckMethodHandler spellCheckMethodHandler) {
    this.spellCheckMethodHandler = spellCheckMethodHandler;
  }

  public interface SpellCheckMethodHandler {
    /**
     * Requests that spell check is initiated for the specified text, which will automatically
     * result in a call to {@code
     * SpellCheckChannel#setSpellCheckMethodHandler(SpellCheckMethodHandler)} once spell check
     * results are received from the native spell check service.
     */
    void initiateSpellCheck(@NonNull String locale, @NonNull String text);
  }
}
