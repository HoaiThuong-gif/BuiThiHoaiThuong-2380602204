package vn.nhombar.nhombar;

import android.app.ActivityManager;
import android.app.admin.DevicePolicyManager;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.speech.tts.TextToSpeech;
import android.speech.tts.Voice;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import org.json.JSONObject;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

// MethodChannel nối lời gọi Dart với API Android; EventChannel chuyển sự kiện về Dart.
public class MainActivity extends FlutterActivity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private TextToSpeech preview;

    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(), "vn.nhombar/push")
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink events) {
                        FamilyPushEvents.sink = events;
                    }

                    @Override
                    public void onCancel(Object arguments) {
                        FamilyPushEvents.sink = null;
                    }
                });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "vn.nhombar/device")
                .setMethodCallHandler(this::handleMethod);
    }

    private void handleMethod(MethodCall call, MethodChannel.Result result) {
        try {
            Vault vault = new Vault(this);
            switch (call.method) {
                case "installationId":
                    result.success(FamilyPushEvents.installation(this));
                    break;
                case "pushToken":
                    if (FirebaseApp.getApps(this).isEmpty()) {
                        result.error("device", "Thông báo trên điện thoại chưa sẵn sàng. Bạn vẫn có thể xem thông báo khi mở NhomBar.", null);
                    } else {
                        FirebaseMessaging.getInstance().getToken().addOnSuccessListener(token -> {
                            vault.put("fcmToken", token);
                            result.success(token);
                        }).addOnFailureListener(exception -> result.error("device",
                                "Chưa đăng ký được thông báo. Hãy kiểm tra mạng rồi thử lại.", null));
                    }
                    break;
                case "initialNotice":
                    String noticeId = getIntent().getStringExtra("noticeId");
                    getIntent().removeExtra("noticeId");
                    result.success(noticeId);
                    break;
                case "markPushRegistered":
                    vault.put("pushRegisteredToken", stringArgument(call, "hash", ""));
                    result.success(null);
                    break;
                case "pushBinding":
                    vault.put("pushBinding", stringArgument(call, "binding", ""));
                    result.success(null);
                    break;
                case "clearFamilyNotifications":
                    FamilyPushEvents.clear(this);
                    result.success(null);
                    break;
                case "language":
                    vault.put("language", "en".equals(call.argument("code")) ? "en" : "vi");
                    result.success(null);
                    break;
                case "voices":
                    listVoices(result);
                    break;
                case "previewVoice":
                    if (preview != null) {
                        if (preview.getVoices() != null) {
                            for (Voice voice : preview.getVoices()) {
                                if (voice.getName().equals(call.argument("voice"))) {
                                    preview.setVoice(voice);
                                    break;
                                }
                            }
                        }
                        preview.speak("Con còn 15 phút sử dụng điện thoại nhé.", TextToSpeech.QUEUE_FLUSH, null, "preview");
                    }
                    result.success(null);
                    break;
                case "credentials":
                    NativeApi.credentials(this, new JSONObject((Map<?, ?>) call.arguments));
                    result.success(null);
                    break;
                case "refreshCredentials":
                    worker.execute(() -> {
                        try {
                            JSONObject tokens = NativeApi.refresh(this);
                            runOnUiThread(() -> result.success(tokens.toString()));
                        } catch (Exception exception) {
                            String code = exception instanceof DeviceProblem
                                    && ((DeviceProblem) exception).sessionExpired ? "session" : "connection";
                            String message = exception instanceof DeviceProblem ? exception.getMessage()
                                    : "Chưa liên lạc được với dịch vụ. Hãy thử lại sau.";
                            runOnUiThread(() -> result.error(code, message, null));
                        }
                    });
                    break;
                case "clearCredentials":
                    if ("true".equals(vault.get("locked"))
                            || getSystemService(DevicePolicyManager.class).isDeviceOwnerApp(getPackageName())) {
                        throw new IllegalStateException("Hãy nhờ bố mẹ kết thúc quản lý điện thoại trước khi đăng xuất.");
                    }
                    stopService(new Intent(this, GuardService.class));
                    String[] names = {"credentials", "deviceId", "policy", "shareLocation", "locationPending",
                            "locationError", "lastSync", "offlineUntil"};
                    for (String name : names) {
                        vault.remove(name);
                    }
                    vault.put("monitoring", "false");
                    result.success(null);
                    break;
                case "link":
                    String linkedDevice = Objects.requireNonNull(call.argument("deviceId"));
                    try (UsageReader reader = new UsageReader(this)) {
                        reader.bindDevice(linkedDevice);
                    }
                    vault.put("deviceId", linkedDevice);
                    result.success(null);
                    break;
                case "shareLocation":
                    boolean enabled = Boolean.TRUE.equals(call.argument("enabled"));
                    vault.put("shareLocation", Boolean.toString(enabled));
                    if (!enabled) {
                        vault.remove("locationPending");
                    }
                    stopService(new Intent(this, GuardService.class));
                    startForegroundService(new Intent(this, GuardService.class));
                    result.success(null);
                    break;
                case "configureConnection":
                    worker.execute(() -> {
                        try {
                            NativeApi.configureEndpoint(this, Objects.requireNonNull(call.argument("baseUrl")));
                            runOnUiThread(() -> result.success(null));
                        } catch (Exception exception) {
                            runOnUiThread(() -> result.error("connection", "Chưa cập nhật được kết nối. Vui lòng mở lại ứng dụng.", null));
                        }
                    });
                    break;
                case "deviceInfo":
                    Map<String, Object> info = new HashMap<>();
                    info.put("name", Build.MANUFACTURER + " " + Build.MODEL);
                    info.put("model", Build.MODEL);
                    info.put("version", Build.VERSION.RELEASE);
                    result.success(info);
                    break;
                case "usageSnapshot":
                    worker.execute(() -> {
                        try (UsageReader reader = new UsageReader(this)) {
                            boolean allowed = reader.allowed();
                            if (allowed) {
                                reader.collect(System.currentTimeMillis());
                            }
                            String day = LocalDate.now(ZoneId.of("Asia/Ho_Chi_Minh")).toString();
                            Map<String, Object> snapshot = new HashMap<>();
                            snapshot.put("allowed", allowed);
                            snapshot.put("date", day);
                            snapshot.put("usedSeconds", allowed ? reader.total(day) : 0);
                            runOnUiThread(() -> result.success(snapshot));
                        } catch (Exception exception) {
                            runOnUiThread(() -> result.error("device", "Chưa đọc được thời gian sử dụng. Hãy kiểm tra quyền trên điện thoại.", null));
                        }
                    });
                    break;
                case "status":
                    try (UsageReader reader = new UsageReader(this)) {
                        Map<String, Object> status = new HashMap<>();
                        status.put("usageAccess", reader.allowed());
                        status.put("deviceId", vault.get("deviceId"));
                        status.put("monitoring", "true".equals(vault.get("monitoring")));
                        status.put("shareLocation", "true".equals(vault.get("shareLocation")));
                        status.put("deviceOwner", getSystemService(DevicePolicyManager.class).isDeviceOwnerApp(getPackageName()));
                        status.put("locked", getSystemService(ActivityManager.class).getLockTaskModeState() == ActivityManager.LOCK_TASK_MODE_LOCKED);
                        status.put("lastSync", vault.get("lastSync"));
                        status.put("locationError", vault.get("locationError"));
                        status.put("error", vault.get("error"));
                        result.success(status);
                    }
                    break;
                case "usageSettings":
                    startActivity(new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:" + getPackageName())));
                    result.success(null);
                    break;
                case "startMonitoring":
                    String device = Objects.requireNonNull(call.argument("deviceId"));
                    boolean allowed;
                    try (UsageReader reader = new UsageReader(this)) {
                        allowed = reader.allowed();
                        if (allowed) {
                            reader.bindDevice(device);
                        }
                    }
                    if (!allowed) {
                        throw new IllegalStateException("Con hãy cho phép xem thời gian sử dụng trước nhé.");
                    }
                    vault.put("deviceId", device);
                    startForegroundService(new Intent(this, GuardService.class));
                    result.success(null);
                    break;
                case "dial":
                    String number = stringArgument(call, "number", "");
                    if (!number.matches("[+0-9 ()-]{1,30}")) {
                        throw new IllegalStateException("Số điện thoại chưa đúng.");
                    }
                    startActivity(new Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", number, null)));
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception exception) {
            String message = exception instanceof IllegalStateException || exception instanceof DeviceProblem
                    ? exception.getMessage() : "Điện thoại chưa thể thực hiện. Hãy thử lại.";
            result.error("device", message, null);
        }
    }

    private static String stringArgument(MethodCall call, String name, String fallback) {
        String value = call.argument(name);
        return value == null ? fallback : value;
    }

    private void listVoices(MethodChannel.Result result) {
        if (preview != null) {
            preview.shutdown();
        }
        preview = new TextToSpeech(this, status -> {
            List<Map<String, Object>> voices = new ArrayList<>();
            if (status == TextToSpeech.SUCCESS && preview != null && preview.getVoices() != null) {
                List<Voice> available = new ArrayList<>();
                for (Voice voice : preview.getVoices()) {
                    if ("vi".equals(voice.getLocale().getLanguage())) {
                        available.add(voice);
                    }
                }
                available.sort(Comparator.comparing(Voice::getName));
                for (Voice voice : available) {
                    Map<String, Object> item = new HashMap<>();
                    item.put("name", voice.getName());
                    item.put("network", voice.isNetworkConnectionRequired());
                    voices.add(item);
                }
            }
            result.success(voices);
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        if ("true".equals(new Vault(this).get("locked"))) {
            startActivity(new Intent(this, RestActivity.class));
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String id = intent.getStringExtra("noticeId");
        if (id != null) {
            FamilyPushEvents.emit("opened", id);
        }
    }

    @Override
    protected void onDestroy() {
        if (preview != null) {
            preview.shutdown();
        }
        worker.shutdown();
        super.onDestroy();
    }
}
