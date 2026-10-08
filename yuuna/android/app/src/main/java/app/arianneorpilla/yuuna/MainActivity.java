// Derived from the AnkiDroid API Sample

package app.arianneorpilla.yuuna;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Log;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import android.net.Uri;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import com.ichi2.anki.FlashCardsContract;
import com.ichi2.anki.api.AddContentApi;
import android.content.ContentValues;
import androidx.core.content.FileProvider;
import android.content.ContentResolver;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import com.ichi2.anki.api.NoteInfo;
import com.ryanheise.audioservice.AudioServiceActivity;
import android.content.res.Configuration;

public class MainActivity extends AudioServiceActivity {
    private static final String ANKIDROID_CHANNEL = "app.arianneorpilla.yuuna/anki";
    private static final String DIAGNOSTICS_CHANNEL = "app.arianneorpilla.yuuna/diagnostics";
    private static final int AD_PERM_REQUEST = 0;

    private static final String CRASH_FILE = "last_java_crash.txt";
    private static final String DIAGNOSTICS_PREFS = "diagnostics";
    private static final String LAST_REPORTED_EXIT = "last_reported_exit_timestamp";
    private static final int MAX_TRACE_LENGTH = 64 * 1024;

    // AnkiDroid queries are IPC calls that can block for seconds, for example
    // while AnkiDroid starts up, so they run off the main thread.
    private final ExecutorService ankiExecutor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private Activity context;
    private AnkiDroidHelper mAnkiDroid;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        isAppRunning = false;
        
        context = MainActivity.this;
        // Create the example data
        mAnkiDroid = new AnkiDroidHelper(context);
        installCrashRecorder();
    }

    /**
     * Records uncaught Java exceptions to a file before the process dies, so
     * the stack trace can be shown when the app is next opened.
     */
    private void installCrashRecorder() {
        Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        if (previous instanceof CrashRecorder) {
            return;
        }
        Thread.setDefaultUncaughtExceptionHandler(
            new CrashRecorder(getApplicationContext(), previous));
    }

    private static class CrashRecorder implements Thread.UncaughtExceptionHandler {
        private final Context appContext;
        private final Thread.UncaughtExceptionHandler previous;

        CrashRecorder(Context appContext, Thread.UncaughtExceptionHandler previous) {
            this.appContext = appContext;
            this.previous = previous;
        }

        @Override
        public void uncaughtException(@NonNull Thread thread, @NonNull Throwable throwable) {
            try (FileWriter writer = new FileWriter(new File(appContext.getFilesDir(), CRASH_FILE))) {
                writer.write("Thread: " + thread.getName() + "\n" + Log.getStackTraceString(throwable));
            } catch (Exception ignored) {
                // Nothing more can be done while the process is dying.
            }

            if (previous != null) {
                previous.uncaughtException(thread, throwable);
            } else {
                android.os.Process.killProcess(android.os.Process.myPid());
                System.exit(10);
            }
        }
    }

    /**
     * Describes why the app's previous process ended, if it ended
     * unexpectedly and has not been reported yet. Returns null otherwise.
     */
    private Map<String, Object> getLastExitReport() {
        Map<String, Object> report = new HashMap<>();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ActivityManager activityManager =
                (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            List<ApplicationExitInfo> exits =
                activityManager.getHistoricalProcessExitReasons(null, 0, 10);
            SharedPreferences prefs = getSharedPreferences(DIAGNOSTICS_PREFS, MODE_PRIVATE);
            long lastReported = prefs.getLong(LAST_REPORTED_EXIT, 0);

            // Exits are ordered newest first.
            for (ApplicationExitInfo exit : exits) {
                if (exit.getTimestamp() <= lastReported) {
                    break;
                }
                if (isUnexpectedExit(exit.getReason())) {
                    report.put("reason", exitReasonName(exit.getReason()));
                    report.put("description", String.valueOf(exit.getDescription()));
                    report.put("timestamp", exit.getTimestamp());
                    report.put("importance", exit.getImportance());
                    report.put("status", exit.getStatus());
                    report.put("pssKb", exit.getPss());
                    report.put("rssKb", exit.getRss());
                    // ANR traces are text; native crash tombstones are binary.
                    if (exit.getReason() == ApplicationExitInfo.REASON_ANR) {
                        try {
                            String trace = readText(exit.getTraceInputStream());
                            if (trace != null) {
                                report.put("trace", trace);
                            }
                        } catch (Exception e) {
                            report.put("trace", "Could not read the trace: " + e);
                        }
                    }
                    break;
                }
            }

            if (!exits.isEmpty()) {
                prefs.edit().putLong(LAST_REPORTED_EXIT, exits.get(0).getTimestamp()).apply();
            }
        }

        File crashFile = new File(getFilesDir(), CRASH_FILE);
        if (crashFile.exists()) {
            try {
                report.put("javaTrace", readText(new FileInputStream(crashFile)));
            } catch (Exception ignored) {
                // The report is best effort.
            }
            crashFile.delete();
            report.putIfAbsent("reason", "CRASH");
        }

        return report.isEmpty() ? null : report;
    }

    private static boolean isUnexpectedExit(int reason) {
        switch (reason) {
            case 2: // REASON_SIGNALED
            case 3: // REASON_LOW_MEMORY
            case 4: // REASON_CRASH
            case 5: // REASON_CRASH_NATIVE
            case 6: // REASON_ANR
            case 7: // REASON_INITIALIZATION_FAILURE
            case 9: // REASON_EXCESSIVE_RESOURCE_USAGE
            case 12: // REASON_DEPENDENCY_DIED
            case 14: // REASON_FREEZER
                return true;
            default:
                return false;
        }
    }

    private static String exitReasonName(int reason) {
        switch (reason) {
            case 2: return "SIGNALED";
            case 3: return "LOW_MEMORY";
            case 4: return "CRASH";
            case 5: return "CRASH_NATIVE";
            case 6: return "ANR";
            case 7: return "INITIALIZATION_FAILURE";
            case 9: return "EXCESSIVE_RESOURCE_USAGE";
            case 12: return "DEPENDENCY_DIED";
            case 14: return "FREEZER";
            default: return "REASON_" + reason;
        }
    }

    private static String readText(InputStream input) throws java.io.IOException {
        if (input == null) {
            return null;
        }
        try (InputStream in = input) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1 && out.size() < MAX_TRACE_LENGTH) {
                out.write(buffer, 0, read);
            }
            String text = out.toString("UTF-8");
            return text.length() > MAX_TRACE_LENGTH ? text.substring(0, MAX_TRACE_LENGTH) : text;
        }
    }
    

    private boolean deckExists(String deck) {
        Long deckId = mAnkiDroid.findDeckIdByName(deck);
        return (deckId != null);
    }

    private boolean modelExists(String model) {
        Long deckId = mAnkiDroid.findModelIdByName(model, 8);
        return (deckId != null);
    }

    private static boolean isAppRunning;

    public static boolean getIsAppRunning() {
        return isAppRunning;
    }

    public void addDefaultModel() {
        final AddContentApi api = new AddContentApi(context);

        long modelId;
        if (modelExists("jidoujisho Kinomoto")) {
            modelId = mAnkiDroid.findModelIdByName("jidoujisho Kinomoto", 17);
        } else {
            modelId = api.addNewCustomModel("jidoujisho Kinomoto",
                new String[] {
                    "Term", 
                    "Reading",
                    "Furigana",
                    "Sentence",
                    "Cloze Before",
                    "Cloze Inside",
                    "Cloze After",
                    "Meaning",
                    "Expanded Meaning",
                    "Collapsed Meaning",
                    "Notes",
                    "Context",
                    "Frequency",
                    "Pitch Accent",
                    "Image",
                    "Term Audio",
                    "Sentence Audio",
                },
                new String[] {
                    "jidoujisho Kinomoto"
                },
                new String[] {
                    "<div id=\"word\">{{Term}}</div>"
                },
                new String[] {
                    "<div id=\"word\">{{#Furigana}}{{furigana:Furigana}}{{/Furigana}}{{^Furigana}}{{Term}}{{/Furigana}}</div>{{#Pitch Accent}}{{Pitch Accent}}{{/Pitch Accent}}\n{{#Image}}<div class=\"image\">{{Image}}</div>{{/Image}}\n{{#Term Audio}}{{Term Audio}}{{/Term Audio}}{{#Sentence Audio}}{{Sentence Audio}}{{/Sentence Audio}}\n<div id=\"sentence\">{{#Cloze Inside}}{{Cloze Before}}<span class=\"cloze\">{{Cloze Inside}}</span>{{Cloze After}}{{/Cloze Inside}}{{^Cloze Inside}}{{Sentence}}{{/Cloze Inside}}</div>\n{{#Meaning}}<p><small>{{Meaning}}</small></p>{{/Meaning}}\n{{#Expanded Meaning}}<p><small>{{Expanded Meaning}}</small></p>{{/Expanded Meaning}}{{#Collapsed Meaning}}<details><summary></summary><p><small>{{Collapsed Meaning}}</small></p></details><br>\n{{/Collapsed Meaning}}"
                },
                ".card {\n  font-family: \"Helvetica Neue\", Arial, sans-serif;\n  font-size: 16px;\n  text-align: center;\n  color: #333333;\n  background-color: #F6F6F6;\n  border-radius: 12px;\n  box-shadow: 0 6px 12px rgba(0, 0, 0, 0.2);\n  padding: 24px;\n  margin: 12px;\n  border: 1px solid #D9D9D9;\n}\n\n#word {\n  font-size: 30px;\n  font-weight: bold;\n  margin-bottom: 16px;\n}\n\n.details-summary {\n  cursor: pointer;\n  font-size: 16px;\n  text-shadow: 1px 1px #ffffff;\n  display: flex;\n  justify-content: space-between;\n  align-items: center;\n  margin-bottom: 16px;\n}\n\n.details-summary:hover {\n  color: #6495ED;\n}\n\n.details-summary:hover .arrow {\n  transform: translateX(4px);\n}\n\n.arrow {\n  fill: #777777;\n  transition: transform 0.2s ease-in-out;\n  margin-right: 8px;\n}\n\n.image img {\n  max-width: 100%;\n  height: 150px;\n  border-radius: 12px;\n  box-shadow: 0 6px 12px rgba(0, 0, 0, 0.2);\n  margin-top: 8px;\n  transition: height 0.2s ease-in-out;\n}\n\n.image:hover img {\n  height: auto;\n}\n\n.furigana {\n  font-size: 22px;\n  font-weight: bold;\n  line-height: 1.4;\n  margin-bottom: 16px;\n  text-shadow: 1px 1px #ffffff;\n}\n\n.meaning {\n  font-size: 18px;\n  line-height: 1.6;\n  margin-bottom: 16px;\n  text-shadow: 1px 1px #ffffff;\n}\n\n.cloze {\n  font-weight: 900\n}\n\n#sentence {\n  font-size: 20px;\n  line-height: 1.6;\n  margin-top: 16px;\n} \n\n.pitch {\n  border-top: solid red 2px;\n  padding-top: 1px;\n}\n\n.pitch_end {\n  border-color: red;\n  border-right: solid red 2px;\n  border-top: solid red 2px;  \n  line-height: 1px;\n  margin-right: 1px;\n  padding-right: 1px;\n  padding-top:1px;\n}",
                    null,
                    null
                    );
        }
    }

    private boolean checkForDuplicates(ArrayList<String> models, String key) {
        final AddContentApi api = new AddContentApi(context);
        for (int i = 0; i < models.size(); i++) {
            String model = models.get(i);
            Long mid = mAnkiDroid.findModelIdByName(model, 1);
            if (mid == null) {
                continue;
            }
            List<NoteInfo> notes = api.findDuplicateNotes(mid, key);
            if (notes != null && !notes.isEmpty()) {
                return true;
            }
        }

        return false;
    }

    private void addNote(String model, String deck, ArrayList<String> fields, ArrayList<String> tags) {
        final AddContentApi api = new AddContentApi(context);

        long deckId;
        if (deckExists(deck)) {
            deckId = mAnkiDroid.findDeckIdByName(deck);
        } else {
            deckId = api.addNewDeck(deck);
        }

        long modelId = mAnkiDroid.findModelIdByName(model, fields.size());
       
        Set<String> allTags = new HashSet<>(Arrays.asList("Yuuna"));
        allTags.addAll(tags);

        api.addNote(modelId, deckId, fields.toArray(new String[fields.size()]), allTags);

        System.out.println("Added note via flutter_ankidroid_api");
        System.out.println("Model: " + modelId);
        System.out.println("Deck: " + deckId);
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ANKIDROID_CHANNEL)
            .setMethodCallHandler(
                (call, result) -> {
                    final String model = call.argument("model");
                    final String deck = call.argument("deck");
                    final String key = call.argument("key");
                    final ArrayList<String> fields = call.argument("fields"); 
                    final ArrayList<String> tags = call.argument("tags"); 
                    final ArrayList<String> models = call.argument("models"); 

                    final String filename = call.argument("filename");
                    final String preferredName = call.argument("preferredName");
                    final String mimeType = call.argument("mimeType");

                    final AddContentApi api = new AddContentApi(context);

                    // AnkiDroid API calls throw when AnkiDroid is missing,
                    // busy or returns no data. Report that to Dart instead of
                    // letting the exception close the app.
                    try {
                        switch (call.method) {
                            case "addNote":
                                addNote(model, deck, fields, tags);
                                result.success("Added note");
                                break;
                            case "checkForDuplicates":
                                if (mAnkiDroid.shouldRequestPermission()) {
                                    result.success(false);
                                    return;
                                } else {
                                    // This runs later on a background thread,
                                    // outside the surrounding try, where an
                                    // uncaught exception would close the app,
                                    // so a failed check reports no duplicate.
                                    ankiExecutor.execute(() -> {
                                        boolean hasDuplicates;
                                        try {
                                            hasDuplicates = checkForDuplicates(models, key);
                                        } catch (Exception e) {
                                            e.printStackTrace();
                                            hasDuplicates = false;
                                        }
                                        final boolean reply = hasDuplicates;
                                        mainHandler.post(() -> result.success(reply));
                                    });
                                }
                                break;
                            case "getDecks":
                                result.success(api.getDeckList());
                                break;
                            case "getModelList":
                                result.success(api.getModelList());
                                break;
                            case "getFieldList":
                                Long mid = mAnkiDroid.findModelIdByName(model, 1);
                                result.success(Arrays.asList(api.getFieldList(mid)));
                                break;
                            case "addDefaultModel":
                                addDefaultModel();
                                break;
                            case "requestAnkidroidPermissions":
                                if (mAnkiDroid.shouldRequestPermission()) {
                                    mAnkiDroid.requestPermission(MainActivity.this, AD_PERM_REQUEST);
                                }
                                result.success(true);
                                break;
                            case "addFileToMedia":
                                System.out.println(filename);
                                System.out.println(preferredName);
                                System.out.println(mimeType);

                                // Workaround from KamWithK
                                // https://github.com/ankidroid/Anki-Android/issues/10335
  
                                File file = new File(filename);

                                Uri file_uri = FileProvider.getUriForFile(context, BuildConfig.APPLICATION_ID + ".provider", file);
                                context.grantUriPermission("com.ichi2.anki", file_uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);

                                ContentValues contentValues = new ContentValues();
                                contentValues.put(FlashCardsContract.AnkiMedia.FILE_URI, file_uri.toString());
                                contentValues.put(FlashCardsContract.AnkiMedia.PREFERRED_NAME, preferredName);

                                ContentResolver contentResolver = context.getContentResolver();
                                Uri returnUri = contentResolver.insert(FlashCardsContract.AnkiMedia.CONTENT_URI, contentValues);

                                result.success(new File(returnUri.getPath()).toString().substring(1));

                                break;
                            default:
                                result.notImplemented();
                        }
                    } catch (Exception e) {
                        e.printStackTrace();
                        result.error("ANKIDROID_ERROR", e.toString(), null);
                    }
                }
            );

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DIAGNOSTICS_CHANNEL)
            .setMethodCallHandler(
                (call, result) -> {
                    if (call.method.equals("getLastExitReport")) {
                        try {
                            result.success(getLastExitReport());
                        } catch (Exception e) {
                            result.error("DIAGNOSTICS_ERROR", e.toString(), null);
                        }
                    } else {
                        result.notImplemented();
                    }
                }
            );
    }
}
