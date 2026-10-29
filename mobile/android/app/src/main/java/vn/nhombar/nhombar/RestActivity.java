package vn.nhombar.nhombar;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.app.admin.DevicePolicyManager;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

// Lock Task cần quyền quản lý thật và Activity đang hiển thị, không phải ghim màn hình.
public class RestActivity extends Activity {
    public static volatile boolean visible;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private Vault vault;
    private TextView status;
    private OnBackInvokedCallback backCallback;
    private String lockProblem;
    private final Runnable check = new Runnable() {
        @Override
        public void run() {
            if (!"true".equals(vault.get("locked"))) {
                exit();
                return;
            }
            enterManagedLock();
            status.setText(NativeText.get(RestActivity.this,
                    lockProblem == null ? "Đang chờ bố mẹ mở khóa từ xa." : lockProblem));
            handler.postDelayed(this, 1000);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        vault = new Vault(this);
        DevicePolicyManager manager = getSystemService(DevicePolicyManager.class);
        if (!manager.isDeviceOwnerApp(getPackageName()) || !manager.isLockTaskPermitted(getPackageName())) {
            finish();
            return;
        }
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER);
        content.setPadding(40, 48, 40, 32);
        content.setBackgroundColor(Color.rgb(240, 249, 249));
        content.addView(text("NhomBar", 22f));
        content.addView(text("Đã đến giờ nghỉ", 28f));
        content.addView(text("Đã đến giờ nghỉ theo lịch hoặc con đã dùng hết thời gian hôm nay. Bố mẹ có thể mở NhomBar trên điện thoại của mình để cho phép dùng tiếp.", 17f));
        JSONObject policy = vault.json("policy");
        JSONObject rule = policy == null ? null : policy.optJSONObject("rule");
        String start = rule == null ? "" : firstFive(rule.optString("startTime"));
        String end = rule == null ? "" : firstFive(rule.optString("endTime"));
        content.addView(text("Giờ sử dụng: " + start + " – " + end
                + "\nNếu đã hết thời gian hôm nay, con có thể dùng lại vào ngày mai.", 16f));
        status = text("Đang chờ bố mẹ mở khóa từ xa.", 15f);
        content.addView(status);

        EditText email = new EditText(this);
        email.setHint(NativeText.get(this, "Email của bố mẹ"));
        email.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        EditText pin = new EditText(this);
        pin.setHint(NativeText.get(this, "Mã phụ huynh gồm 6 số"));
        pin.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        pin.setFilters(new InputFilter[]{new InputFilter.LengthFilter(6)});
        content.addView(email);
        content.addView(pin);
        Button open = new Button(this);
        open.setText(NativeText.get(this, "Bố mẹ cho phép dùng thêm 15 phút"));
        content.addView(open);
        open.setOnClickListener(view -> {
            open.setEnabled(false);
            String parentEmail = email.getText().toString().trim();
            String parentPin = pin.getText().toString();
            worker.execute(() -> {
                try {
                    String device = vault.get("deviceId");
                    if (device == null) {
                        throw new IllegalStateException("Chưa kết nối điện thoại.");
                    }
                    JSONObject currentPolicy = new JSONObject(NativeApi.request(this, "/api/devices/" + device + "/policy"));
                    JSONObject body = new JSONObject();
                    body.put("email", parentEmail);
                    body.put("pin", parentPin);
                    body.put("version", currentPolicy.getJSONObject("state").getLong("policyVersion"));
                    NativeApi.request(this, "/api/devices/" + device + "/parent-unlock", body.toString());
                    String updatedPolicy = NativeApi.request(this, "/api/devices/" + device + "/policy");
                    vault.put("policy", updatedPolicy);
                    vault.put("server", new JSONObject(updatedPolicy).getString("serverTime"));
                    vault.put("anchor", Long.toString(SystemClock.elapsedRealtime()));
                    vault.put("locked", "false");
                    runOnUiThread(() -> {
                        pin.getText().clear();
                        exit();
                    });
                } catch (Exception exception) {
                    runOnUiThread(() -> {
                        String fallback = "Cần có mạng để xác nhận với bố mẹ. Hãy thử lại.";
                        String message = exception instanceof DeviceProblem && exception.getMessage() != null
                                ? exception.getMessage() : fallback;
                        Toast.makeText(this, NativeText.get(this, message), Toast.LENGTH_LONG).show();
                        open.setEnabled(true);
                        pin.getText().clear();
                    });
                }
            });
        });
        Button call = new Button(this);
        call.setText(NativeText.get(this, "Gọi bố mẹ hoặc liên hệ khẩn cấp"));
        call.setOnClickListener(view -> {
            try {
                startActivity(new Intent(Intent.ACTION_DIAL, Uri.parse("tel:")));
            } catch (Exception exception) {
                Toast.makeText(this, "Hãy nhờ người lớn gần con giúp đỡ.", Toast.LENGTH_LONG).show();
            }
        });
        content.addView(call);
        Button recovery = new Button(this);
        recovery.setText(NativeText.get(this, "Bố mẹ dùng mã mở khóa khi mất mạng"));
        recovery.setOnClickListener(view -> showRecovery());
        content.addView(recovery);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        setContentView(scroll);
        // Android mới dùng callback Back; bản cũ vẫn có onBackPressed bên dưới.
        if (Build.VERSION.SDK_INT >= 33) {
            backCallback = () -> {
                if (!"true".equals(vault.get("locked"))) {
                    exit();
                }
            };
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_DEFAULT, backCallback);
        }
        handler.post(check);
    }

    private TextView text(String value, float size) {
        TextView label = new TextView(this);
        label.setText(NativeText.get(this, value));
        label.setTextSize(size);
        label.setGravity(Gravity.CENTER);
        label.setTextColor(Color.rgb(24, 63, 67));
        label.setPadding(0, 12, 0, 16);
        return label;
    }

    private static String firstFive(String value) {
        return value.substring(0, Math.min(5, value.length()));
    }

    private void showRecovery() {
        EditText input = new EditText(this);
        input.setHint(NativeText.get(this, "Mã riêng bố mẹ đã lưu"));
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        new AlertDialog.Builder(this)
                .setTitle(NativeText.get(this, "Mở khóa khi mất mạng"))
                .setMessage(NativeText.get(this, "Nhập mã dùng một lần đã được bố mẹ chuẩn bị trước. Điện thoại sẽ mở trong 15 phút để kết nối lại mạng."))
                .setView(input)
                .setNegativeButton(NativeText.get(this, "Hủy"), null)
                .setPositiveButton(NativeText.get(this, "Mở khóa"), (dialog, which) -> {
                    String code = input.getText().toString().replace(" ", "").toUpperCase(Locale.ROOT);
                    try {
                        byte[] digest = MessageDigest.getInstance("SHA-256").digest(code.getBytes(StandardCharsets.UTF_8));
                        StringBuilder hash = new StringBuilder();
                        for (byte value : digest) {
                            hash.append(String.format(Locale.ROOT, "%02X", value & 0xff));
                        }
                        JSONObject policy = vault.json("policy");
                        JSONObject recovery = policy == null ? null : policy.optJSONObject("recovery");
                        String expected = recovery == null ? null : recovery.optString("hash");
                        if (code.length() == 20 && Objects.equals(hash.toString(), expected)
                                && !hash.toString().equals(vault.get("consumedRecovery"))) {
                            vault.put("consumedRecovery", hash.toString());
                            vault.put("recoveryReceipt", hash.toString());
                            vault.put("offlineBoot", Integer.toString(Settings.Global.getInt(
                                    getContentResolver(), Settings.Global.BOOT_COUNT, 0)));
                            vault.put("offlineUntil", Long.toString(SystemClock.elapsedRealtime() + 15 * 60 * 1000));
                            vault.put("locked", "false");
                            exit();
                        } else {
                            Toast.makeText(this, "Mã chưa đúng hoặc đã được sử dụng.", Toast.LENGTH_LONG).show();
                        }
                    } catch (java.security.NoSuchAlgorithmException exception) {
                        throw new IllegalStateException(exception);
                    }
                })
                .show();
    }

    private void enterManagedLock() {
        if (!visible || !"true".equals(vault.get("locked"))
                || getSystemService(KeyguardManager.class).isKeyguardLocked()) {
            return;
        }
        DevicePolicyManager manager = getSystemService(DevicePolicyManager.class);
        if (!manager.isDeviceOwnerApp(getPackageName()) || !manager.isLockTaskPermitted(getPackageName())) {
            lockProblem = "Chưa có quyền tự khóa. Bố mẹ cần kiểm tra thiết lập điện thoại.";
            return;
        }
        ActivityManager activityManager = getSystemService(ActivityManager.class);
        if (activityManager.getLockTaskModeState() == ActivityManager.LOCK_TASK_MODE_LOCKED) {
            lockProblem = null;
            return;
        }
        try {
            startLockTask();
            lockProblem = activityManager.getLockTaskModeState() == ActivityManager.LOCK_TASK_MODE_LOCKED
                    ? null : "Chưa áp dụng được khóa. Bố mẹ cần kiểm tra thiết lập điện thoại.";
        } catch (Exception exception) {
            lockProblem = "Chưa áp dụng được khóa. Bố mẹ cần kiểm tra thiết lập điện thoại.";
        }
        if (lockProblem != null) {
            vault.put("error", lockProblem);
        }
    }

    private void exit() {
        try {
            stopLockTask();
        } catch (Exception ignored) {
            // Có thể Activity chưa vào chế độ khóa.
        }
        finish();
    }

    @Override
    protected void onResume() {
        super.onResume();
        visible = true;
        enterManagedLock();
    }

    @Override
    protected void onPause() {
        visible = false;
        super.onPause();
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (!"true".equals(vault.get("locked"))) {
            exit();
        }
    }

    @Override
    protected void onDestroy() {
        if (Build.VERSION.SDK_INT >= 33 && backCallback != null) {
            getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(backCallback);
        }
        handler.removeCallbacksAndMessages(null);
        worker.shutdownNow();
        visible = false;
        super.onDestroy();
    }
}
