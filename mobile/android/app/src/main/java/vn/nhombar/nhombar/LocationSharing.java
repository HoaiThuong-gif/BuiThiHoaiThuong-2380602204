package vn.nhombar.nhombar;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;

public class LocationSharing implements LocationListener {
    private final Context context;
    private final LocationManager manager;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Vault vault;
    private final AtomicBoolean sending = new AtomicBoolean(false);
    private volatile boolean stopped;

    public LocationSharing(Context context) {
        this.context = context;
        manager = context.getSystemService(LocationManager.class);
        vault = new Vault(context);
    }

    public boolean allowed() {
        boolean locationAllowed = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED
                || context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
        boolean backgroundAllowed = Build.VERSION.SDK_INT < 29
                || context.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
        boolean notificationAllowed = Build.VERSION.SDK_INT < 33
                || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED;
        return "true".equals(vault.get("shareLocation")) && locationAllowed
                && backgroundAllowed && notificationAllowed;
    }

    public void start() {
        handler.post(() -> {
            if (stopped || !allowed()) {
                return;
            }
            try {
                boolean precise = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                        == PackageManager.PERMISSION_GRANTED;
                List<String> providers = new ArrayList<>();
                for (String provider : manager.getAllProviders()) {
                    if (LocationManager.NETWORK_PROVIDER.equals(provider)
                            || precise && LocationManager.GPS_PROVIDER.equals(provider)) {
                        providers.add(provider);
                    }
                }
                if (providers.isEmpty()) {
                    vault.put("locationError", "Chưa tìm thấy cách lấy vị trí. Hãy kiểm tra cài đặt vị trí trên điện thoại.");
                }
                boolean providerEnabled = false;
                for (String provider : providers) {
                    manager.requestLocationUpdates(provider, 10000L, 0f, this, Looper.getMainLooper());
                    if (manager.isProviderEnabled(provider)) {
                        providerEnabled = true;
                    }
                }
                if (!providerEnabled) {
                    vault.put("locationError", "Hãy bật vị trí trên điện thoại để tiếp tục chia sẻ.");
                }
            } catch (SecurityException exception) {
                vault.put("locationError", "Hãy kiểm tra quyền chia sẻ vị trí.");
            }
        });
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onLocationChanged(Location location) {
        if (stopped || !allowed()) {
            return;
        }
        boolean mock = Build.VERSION.SDK_INT >= 31 ? location.isMock() : location.isFromMockProvider();
        if (mock) {
            vault.put("locationError", "Điện thoại đang dùng vị trí giả. Hãy tắt ứng dụng tạo vị trí giả.");
            return;
        }
        if (!Float.isFinite(location.getAccuracy()) || location.getAccuracy() < 0) {
            return;
        }
        try {
            JSONObject body = new JSONObject();
            body.put("latitude", location.getLatitude());
            body.put("longitude", location.getLongitude());
            body.put("accuracy", (double) location.getAccuracy());
            body.put("recordedAt", Instant.ofEpochMilli(location.getTime()).toString());
            // Chỉ giữ điểm chưa gửi mới nhất khi mất mạng.
            synchronized (LocationSharing.class) {
                String pending = vault.get("locationPending");
                if (pending != null) {
                    try {
                        String previous = new JSONObject(pending).optString("recordedAt");
                        if (Instant.parse(previous).toEpochMilli() >= location.getTime()) {
                            return;
                        }
                    } catch (Exception ignored) {
                        // Điểm cũ không hợp lệ được thay bằng điểm mới.
                    }
                }
                vault.put("locationPending", body.toString());
            }
        } catch (org.json.JSONException exception) {
            throw new IllegalStateException(exception);
        }
        vault.remove("locationError");
        if (!sending.compareAndSet(false, true)) {
            return;
        }
        try {
            worker.execute(() -> {
                try {
                    if (stopped || !allowed()) {
                        return;
                    }
                    String device = vault.get("deviceId");
                    String pending = vault.get("locationPending");
                    if (device == null || pending == null) {
                        return;
                    }
                    try {
                        NativeApi.request(context, "/api/devices/" + device + "/locations", pending);
                        synchronized (LocationSharing.class) {
                            if (pending.equals(vault.get("locationPending"))) {
                                vault.remove("locationPending");
                            }
                        }
                    } catch (Exception exception) {
                        vault.put("locationError", "Vị trí mới đang chờ kết nối để gửi cho bố mẹ.");
                    }
                } finally {
                    sending.set(false);
                }
            });
        } catch (RejectedExecutionException exception) {
            sending.set(false);
        }
    }

    @Override
    public void onProviderEnabled(String provider) {
        vault.remove("locationError");
    }

    @Override
    public void onProviderDisabled(String provider) {
        for (String enabled : manager.getProviders(true)) {
            if (LocationManager.GPS_PROVIDER.equals(enabled) || LocationManager.NETWORK_PROVIDER.equals(enabled)) {
                return;
            }
        }
        vault.put("locationError", "Hãy bật vị trí trên điện thoại để tiếp tục chia sẻ.");
    }

    @Override
    @Deprecated
    public void onStatusChanged(String provider, int status, Bundle extras) { }

    public void stop() {
        stopped = true;
        handler.post(() -> manager.removeUpdates(this));
        worker.shutdownNow();
    }
}
