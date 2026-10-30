package vn.nhombar.nhombar;

import android.Manifest;
import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.SystemClock;
import android.provider.Settings;
import android.speech.tts.TextToSpeech;
import android.speech.tts.Voice;
import android.telecom.TelecomManager;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

// Tách kiểm tra thời gian cục bộ khỏi luồng mạng để mạng chậm không chặn lời nhắc.
public class GuardService extends Service implements TextToSpeech.OnInitListener {
    private final ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();
    private final ScheduledExecutorService localExecutor = Executors.newSingleThreadScheduledExecutor();
    private int localTicks;
    private Vault vault;
    private UsageReader usage;
    private TextToSpeech voice;
    private LocationSharing location;
    private volatile boolean voiceReady;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onInit(int status) {
        if (status == TextToSpeech.SUCCESS) {
            voiceReady = voice.setLanguage(Locale.forLanguageTag("vi-VN")) >= 0;
        }
        if (!voiceReady) {
            vault.put("error", "Điện thoại chưa có giọng tiếng Việt. Hãy nhờ bố mẹ tải giọng đọc trong cài đặt điện thoại.");
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        vault = new Vault(this);
        usage = new UsageReader(this);
        voice = new TextToSpeech(this, this);
        getSystemService(NotificationManager.class).createNotificationChannel(new NotificationChannel(
                "nhombar_guard", "Lời nhắc thời gian", NotificationManager.IMPORTANCE_DEFAULT));
        location = new LocationSharing(this);
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        String title = location.allowed() ? "NhomBar đang chia sẻ vị trí và thời gian sử dụng"
                : "NhomBar đang cập nhật thời gian sử dụng";
        Notification notification = new Notification.Builder(this, "nhombar_guard")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(NativeText.get(this, title))
                .setContentText(NativeText.get(this, "Con và bố mẹ cùng theo dõi thói quen dùng điện thoại."))
                .setContentIntent(open)
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 34) {
            int types = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE;
            if (location.allowed()) {
                types |= ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION;
            }
            startForeground(2380, notification, types);
        } else {
            startForeground(2380, notification);
        }
        location.start();
        executor.scheduleWithFixedDelay(this::tick, 0, 15, TimeUnit.SECONDS);
        // Đồng hồ cục bộ chạy riêng, không phải chờ yêu cầu mạng hoàn tất.
        localExecutor.scheduleWithFixedDelay(() -> {
            String device = vault.get("deviceId");
            if (device != null) {
                try {
                    if (localTicks++ % 5 == 0) {
                        usage.collect(System.currentTimeMillis());
                    }
                    enforce(device);
                } catch (Exception exception) {
                    vault.put("error", "Hãy nhờ bố mẹ kiểm tra quyền xem thời gian sử dụng và thiết lập điện thoại.");
                }
            }
        }, 0, 1, TimeUnit.SECONDS);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        vault.put("monitoring", "true");
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        vault.put("monitoring", "false");
        executor.shutdownNow();
        localExecutor.shutdownNow();
        voice.shutdown();
        location.stop();
        usage.close();
        super.onDestroy();
    }

    private void tick() {
        String device = vault.get("deviceId");
        if (device == null) {
            return;
        }
        try {
            JSONObject policy = new JSONObject(NativeApi.request(this, "/api/devices/" + device + "/policy"));
            synchronized (this) {
                JSONObject previous = vault.json("policy");
                if (previous != null && policy.getJSONObject("rule").optLong("version")
                        < previous.getJSONObject("rule").optLong("version")) {
                    throw new IllegalStateException("Đang chờ cài đặt mới nhất.");
                }
                if (previous != null && policy.getJSONObject("state").optLong("policyVersion")
                        < previous.getJSONObject("state").optLong("policyVersion")) {
                    throw new IllegalStateException("Đang chờ trạng thái mới nhất.");
                }
                if (previous != null && recoveryVersion(policy) < recoveryVersion(previous)) {
                    throw new IllegalStateException("Đang chờ mã dự phòng mới nhất.");
                }
                vault.put("policy", policy.toString());
                vault.put("anchor", Long.toString(SystemClock.elapsedRealtime()));
                vault.put("boot", bootCount());
                vault.put("server", policy.getString("serverTime"));
                vault.put("lastSync", Instant.now().toString());
                vault.remove("error");
                if (Math.abs(OffsetDateTime.parse(policy.getString("serverTime")).toInstant().toEpochMilli()
                        - System.currentTimeMillis()) <= 120000) {
                    usage.confirmClock();
                }
            }
            try {
                try {
                    registerPush();
                } catch (Exception exception) {
                    vault.put("pushRegistrationError", "Chưa đăng ký được thông báo. Báo cáo sử dụng vẫn tiếp tục cập nhật.");
                }
                UsageReader.PendingUsage pendingUsage = usage.pending();
                if (!pendingUsage.ids.isEmpty()) {
                    NativeApi.request(this, "/api/devices/" + device + "/usage", pendingUsage.records.toString());
                    usage.remove(pendingUsage.ids);
                }
                if ("true".equals(vault.get("shareLocation"))) {
                    String pending = vault.get("locationPending");
                    if (pending != null && location.allowed()) {
                        NativeApi.request(this, "/api/devices/" + device + "/locations", pending);
                        synchronized (LocationSharing.class) {
                            if (pending.equals(vault.get("locationPending"))) {
                                vault.remove("locationPending");
                            }
                        }
                    }
                }
                String receipt = vault.get("recoveryReceipt");
                if (receipt != null) {
                    try {
                        NativeApi.request(this, "/api/devices/" + device + "/recovery-used",
                                new JSONObject().put("hash", receipt).toString());
                        vault.remove("recoveryReceipt");
                    } catch (Exception ignored) {
                        // Giữ xác nhận để gửi lại khi có mạng.
                    }
                }
            } catch (Exception exception) {
                vault.put("error", "Chưa gửi được báo cáo. Giới hạn và lệnh của bố mẹ vẫn được cập nhật.");
            }
            boolean actualLock = getSystemService(ActivityManager.class).getLockTaskModeState()
                    == ActivityManager.LOCK_TASK_MODE_LOCKED;
            DevicePolicyManager manager = getSystemService(DevicePolicyManager.class);
            JSONObject acknowledgement = new JSONObject();
            acknowledgement.put("version", policy.getJSONObject("state").getLong("policyVersion"));
            acknowledgement.put("isLocked", actualLock);
            acknowledgement.put("deviceOwner", manager.isDeviceOwnerApp(getPackageName()));
            NativeApi.request(this, "/api/devices/" + device + "/ack", acknowledgement.toString());
        } catch (Exception exception) {
            String message = exception instanceof DeviceProblem ? exception.getMessage()
                    : "Chưa cập nhật được. Giới hạn đã đặt vẫn được giữ.";
            vault.put("error", message == null ? "Chưa cập nhật được." : message);
        }
    }

    private static long recoveryVersion(JSONObject policy) {
        JSONObject recovery = policy.optJSONObject("recovery");
        return recovery == null ? 0 : recovery.optLong("version", 0);
    }

    private void registerPush() throws Exception {
        String token = vault.get("fcmToken");
        if (token == null) {
            return;
        }
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8));
        StringBuilder hash = new StringBuilder();
        for (byte value : digest) {
            hash.append(String.format(Locale.ROOT, "%02X", value & 0xff));
        }
        if (!hash.toString().equals(vault.get("pushRegisteredToken"))) {
            JSONObject body = new JSONObject();
            body.put("token", token);
            body.put("installationId", FamilyPushEvents.installation(this));
            JSONObject registered = new JSONObject(NativeApi.request(this, "/api/push/register", body.toString()));
            vault.put("pushBinding", registered.getString("binding"));
            vault.put("pushRegisteredToken", hash.toString());
        }
    }

    @SuppressWarnings("deprecation")
    private synchronized void enforce(String device) throws Exception {
        JSONObject policy = vault.json("policy");
        if (policy == null) {
            return;
        }
        JSONObject rule = policy.optJSONObject("rule");
        if (rule == null) {
            return;
        }
        JSONObject state = policy.getJSONObject("state");
        Instant release = optionalInstant(policy.optString("releaseUntil"));
        long delta = SystemClock.elapsedRealtime() - savedLong("anchor", 0);
        boolean synchronizedRecently = delta >= 0 && delta <= 60000 && bootCount().equals(vault.get("boot"));
        if (release != null && synchronizedRecently
                && release.isAfter(OffsetDateTime.parse(policy.getString("serverTime")).toInstant().plusMillis(delta))) {
            DevicePolicyManager manager = getSystemService(DevicePolicyManager.class);
            vault.put("locked", "false");
            if (manager.isDeviceOwnerApp(getPackageName())) {
                ComponentName admin = new ComponentName(this, FamilyAdminReceiver.class);
                manager.setLockTaskPackages(admin, new String[0]);
                if (Build.VERSION.SDK_INT >= 30) {
                    manager.setUserControlDisabledPackages(admin, Collections.emptyList());
                }
                manager.clearDeviceOwnerApp(getPackageName());
            }
            JSONObject acknowledgement = new JSONObject();
            acknowledgement.put("version", state.getLong("policyVersion"));
            acknowledgement.put("isLocked", false);
            acknowledgement.put("deviceOwner", false);
            NativeApi.request(this, "/api/devices/" + device + "/ack", acknowledgement.toString());
            vault.put("monitoring", "false");
            stopSelf();
            return;
        }
        String savedAnchor = vault.get("anchor");
        if (savedAnchor == null) {
            return;
        }
        long anchor = Long.parseLong(savedAnchor);
        boolean rebooted = SystemClock.elapsedRealtime() < anchor || !bootCount().equals(vault.get("boot"));
        Instant trusted = OffsetDateTime.parse(vault.get("server")).toInstant();
        if (!rebooted) {
            trusted = trusted.plusMillis(SystemClock.elapsedRealtime() - anchor);
        }
        ZonedDateTime local = trusted.atZone(ZoneId.of("Asia/Ho_Chi_Minh"));
        String today = local.toLocalDate().toString();
        boolean sameDay = today.equals(policy.getString("usageDate"));
        int used = Math.max(usage.total(today), sameDay ? policy.optInt("usedSeconds") : 0)
                + usage.activeSeconds(System.currentTimeMillis());
        int limit = rule.getInt("dailyLimitMinutes") * 60 + (sameDay ? policy.optInt("extraMinutes") * 60 : 0);
        int remaining = limit - used;
        LocalTime start = LocalTime.parse(rule.getString("startTime"));
        LocalTime end = LocalTime.parse(rule.getString("endTime"));
        boolean inHours = !local.toLocalTime().isBefore(start) && local.toLocalTime().isBefore(end);
        Instant unlock = optionalInstant(state.optString("unlockAt"));
        boolean offlineGrace = bootCount().equals(vault.get("offlineBoot"))
                && savedLong("offlineUntil", 0) > SystemClock.elapsedRealtime();
        boolean grace = unlock != null && unlock.isAfter(trusted) && !rebooted || offlineGrace;
        boolean changedClock = Math.abs(trusted.toEpochMilli() - System.currentTimeMillis()) > 120000
                || usage.clockProblem();
        if (changedClock) {
            vault.put("error", "Giờ trên điện thoại chưa đúng. Hãy bật đặt giờ tự động rồi kết nối mạng.");
        }
        if (!usage.allowed()) {
            vault.put("error", "Quyền xem thời gian sử dụng đã bị tắt. Hãy nhờ bố mẹ bật lại.");
        }
        boolean shouldLock = rule.optBoolean("isEnabled") && rule.optBoolean("strictMode") && !grace
                && (!inHours || remaining <= 0 || rebooted || changedClock || !usage.allowed());
        vault.put("remaining", Integer.toString(Math.max(0, remaining)));
        if (rule.optBoolean("isEnabled") && !grace) {
            warn(policy, rule, state, today, remaining, inHours);
        }
        DevicePolicyManager manager = getSystemService(DevicePolicyManager.class);
        if (shouldLock) {
            if (!manager.isDeviceOwnerApp(getPackageName())) {
                vault.put("locked", "false");
                if ("Chưa thể áp dụng giới hạn vì điện thoại chưa được thiết lập quyền khóa. Hãy nhờ bố mẹ kiểm tra.".equals(vault.get("error"))) {
                    vault.remove("error");
                }
                return;
            }
            ComponentName admin = new ComponentName(this, FamilyAdminReceiver.class);
            String dialer = getSystemService(TelecomManager.class).getDefaultDialerPackage();
            Set<String> packages = new LinkedHashSet<>();
            packages.add(getPackageName());
            if (dialer != null) {
                packages.add(dialer);
            }
            packages.add("com.android.emergency");
            manager.setLockTaskPackages(admin, packages.toArray(new String[0]));
            if (Build.VERSION.SDK_INT >= 28) {
                manager.setLockTaskFeatures(admin, DevicePolicyManager.LOCK_TASK_FEATURE_GLOBAL_ACTIONS
                        | DevicePolicyManager.LOCK_TASK_FEATURE_KEYGUARD);
            }
            vault.put("locked", "true");
            if (!RestActivity.visible && getSystemService(ActivityManager.class).getLockTaskModeState()
                    != ActivityManager.LOCK_TASK_MODE_LOCKED) {
                startActivity(new Intent(this, RestActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            }
        } else {
            vault.put("locked", "false");
        }
    }

    private void warn(JSONObject policy, JSONObject rule, JSONObject state, String today,
                      int remaining, boolean inHours) {
        String cycle = today + ":" + rule.optLong("version") + ":" + state.optLong("policyVersion")
                + ":" + policy.optInt("extraMinutes");
        String chosenVoice = rule.optString("voiceName");
        if (voiceReady && !chosenVoice.trim().isEmpty() && voice.getVoices() != null) {
            for (Voice candidate : voice.getVoices()) {
                if (candidate.getName().equals(chosenVoice)) {
                    voice.setVoice(candidate);
                    break;
                }
            }
        }
        Set<Integer> thresholds = new TreeSet<>(Collections.reverseOrder());
        thresholds.add(0);
        for (String part : rule.optString("warningMinutes", "30,15,5").split(",")) {
            try {
                int threshold = Integer.parseInt(part);
                if (threshold >= 1 && threshold <= 120) {
                    thresholds.add(threshold);
                }
            } catch (NumberFormatException ignored) {
                // Bỏ mốc không phải số để tiếp tục đọc những mốc còn lại.
            }
        }
        for (int threshold : thresholds) {
            boolean reached = threshold == 0 ? !inHours || remaining <= 0
                    : inHours && remaining <= threshold * 60 && remaining > (threshold - 2) * 60;
            if (reached) {
                String message = threshold == 0 ? "Thời gian sử dụng điện thoại hôm nay đã kết thúc."
                        : "Con còn " + threshold + " phút sử dụng điện thoại. Hãy chuẩn bị kết thúc hoạt động hiện tại nhé.";
                if (voiceReady && !usage.hasWarned(cycle, threshold + 1000)
                        && voice.speak(message, TextToSpeech.QUEUE_ADD, null, cycle + ":" + threshold) == TextToSpeech.SUCCESS) {
                    usage.warned(cycle, threshold + 1000);
                }
                boolean canNotify = Build.VERSION.SDK_INT < 33
                        || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
                if (canNotify && !usage.warned(cycle, threshold)) {
                    Notification notification = new Notification.Builder(this, "nhombar_guard")
                            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                            .setContentTitle(NativeText.get(this, "Lời nhắc cho con"))
                            .setContentText(NativeText.get(this, message))
                            .build();
                    getSystemService(NotificationManager.class).notify(2381, notification);
                }
            }
        }
    }

    private Instant optionalInstant(String value) {
        if (value.trim().isEmpty() || "null".equals(value)) {
            return null;
        }
        return OffsetDateTime.parse(value).toInstant();
    }

    private long savedLong(String name, long fallback) {
        String value = vault.get(name);
        return value == null ? fallback : Long.parseLong(value);
    }

    private String bootCount() {
        return Integer.toString(Settings.Global.getInt(getContentResolver(), Settings.Global.BOOT_COUNT, 0));
    }
}
