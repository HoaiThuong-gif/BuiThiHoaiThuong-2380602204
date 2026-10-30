package vn.nhombar.nhombar;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import io.flutter.plugin.common.EventChannel;
import org.json.JSONArray;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public final class FamilyPushEvents {
    public static volatile EventChannel.EventSink sink;

    private FamilyPushEvents() { }

    public static void emit(String kind) {
        emit(kind, null);
    }

    public static void emit(String kind, String id) {
        new Handler(Looper.getMainLooper()).post(() -> {
            EventChannel.EventSink current = sink;
            if (current != null) {
                Map<String, Object> event = new HashMap<>();
                event.put("kind", kind);
                event.put("id", id);
                current.success(event);
            }
        });
    }

    public static synchronized String installation(Context context) {
        Vault vault = new Vault(context);
        String id = vault.get("installationId");
        if (id == null) {
            id = UUID.randomUUID().toString();
            vault.put("installationId", id);
        }
        return id;
    }

    public static void channel(Context context) {
        NotificationChannel channel = new NotificationChannel("nhombar_family", "Thông báo gia đình",
                NotificationManager.IMPORTANCE_HIGH);
        channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
        context.getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    private static JSONArray seen(Vault vault) {
        try {
            String value = vault.get("pushSeen");
            return new JSONArray(value == null ? "[]" : value);
        } catch (Exception exception) {
            return new JSONArray();
        }
    }

    public static synchronized void show(Context context, String id, String binding) {
        try {
            UUID.fromString(id);
        } catch (Exception exception) {
            return;
        }
        Vault vault = new Vault(context);
        if (binding.trim().isEmpty() || !binding.equals(vault.get("pushBinding"))) {
            return;
        }
        JSONArray previous = seen(vault);
        for (int index = 0; index < previous.length(); index++) {
            if (id.equals(previous.optString(index))) {
                return;
            }
        }
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            return;
        }
        channel(context);
        Intent intent = new Intent(context, MainActivity.class).putExtra("noticeId", id)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent open = PendingIntent.getActivity(context, id.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification notification = new Notification.Builder(context, "nhombar_family")
                .setSmallIcon(R.drawable.ic_nhombar)
                .setContentTitle("NhomBar")
                .setContentText("Gia đình có thông báo mới. Mở NhomBar để xem nhé.")
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setContentIntent(open)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .build();
        context.getSystemService(NotificationManager.class).notify(id, 0, notification);
        JSONArray next = new JSONArray();
        for (int index = Math.max(0, previous.length() - 49); index < previous.length(); index++) {
            next.put(previous.optString(index));
        }
        next.put(id);
        vault.put("pushSeen", next.toString());
        emit("received", id);
    }

    public static void clear(Context context) {
        Vault vault = new Vault(context);
        JSONArray previous = seen(vault);
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        for (int index = 0; index < previous.length(); index++) {
            manager.cancel(previous.optString(index), 0);
        }
        vault.remove("pushSeen");
        vault.remove("pushBinding");
    }
}
