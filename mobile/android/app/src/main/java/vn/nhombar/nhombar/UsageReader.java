package vn.nhombar.nhombar;

import android.app.AppOpsManager;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.os.Process;
import android.os.SystemClock;
import android.provider.Settings;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.TimeUnit;

// UsageStatsManager đọc lịch sử Android; SQLite giữ hàng đợi chưa gửi lên máy chủ.
public class UsageReader extends SQLiteOpenHelper {
    private final Context context;
    private String homePackage;
    private boolean homeResolved;
    private static final ZoneId USAGE_ZONE = ZoneId.of("Asia/Ho_Chi_Minh");

    public UsageReader(Context context) {
        super(context, "usage_queue.db", null, 1);
        this.context = context;
    }

    @Override
    public void onCreate(SQLiteDatabase database) {
        database.execSQL("CREATE TABLE queue(id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT NOT NULL)");
        database.execSQL("CREATE TABLE state(name TEXT PRIMARY KEY, value TEXT NOT NULL)");
        database.execSQL("CREATE TABLE warnings(day TEXT NOT NULL, threshold INTEGER NOT NULL, at TEXT NOT NULL, PRIMARY KEY(day,threshold))");
    }

    @Override
    public void onUpgrade(SQLiteDatabase database, int oldVersion, int newVersion) { }

    public boolean allowed() {
        AppOpsManager manager = context.getSystemService(AppOpsManager.class);
        return manager.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(), context.getPackageName()) == AppOpsManager.MODE_ALLOWED;
    }

    private String state(String name) {
        try (Cursor cursor = getReadableDatabase().rawQuery(
                "SELECT value FROM state WHERE name=?", new String[]{name})) {
            return cursor.moveToFirst() ? cursor.getString(0) : null;
        }
    }

    private void save(String name, String value) {
        ContentValues values = new ContentValues();
        values.put("name", name);
        values.put("value", value);
        getWritableDatabase().insertWithOnConflict("state", null, values, SQLiteDatabase.CONFLICT_REPLACE);
    }

    private String homePackage() {
        if (!homeResolved) {
            ResolveInfo home = context.getPackageManager().resolveActivity(
                    new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                    PackageManager.MATCH_DEFAULT_ONLY);
            homePackage = home != null && home.activityInfo != null ? home.activityInfo.packageName : null;
            homeResolved = true;
        }
        return homePackage;
    }

    public void bindDevice(String deviceId) {
        if (deviceId.equals(state("device"))) {
            return;
        }
        SQLiteDatabase database = getWritableDatabase();
        database.beginTransaction();
        try {
            database.delete("queue", null, null);
            database.delete("warnings", null, null);
            database.delete("state", null, null);
            save("device", deviceId);
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    public void collect(long until) throws JSONException {
        if (!allowed()) {
            throw new IllegalStateException("Hãy cho phép xem thời gian sử dụng để tiếp tục cập nhật.");
        }
        String savedCursor = state("cursor");
        long cursor = savedCursor != null ? Long.parseLong(savedCursor)
                : Instant.ofEpochMilli(until).atZone(USAGE_ZONE).toLocalDate()
                    .atStartOfDay(USAGE_ZONE).toInstant().toEpochMilli();
        long elapsed = SystemClock.elapsedRealtime();
        String boot = bootCount();
        String previousElapsed = state("elapsed");
        boolean sameBoot = boot.equals(state("boot"));
        if (previousElapsed != null && sameBoot
                && Math.abs((until - cursor) - (elapsed - Long.parseLong(previousElapsed))) > 5000) {
            save("clockProblem", "true");
            save("cursor", Long.toString(until));
            save("elapsed", Long.toString(elapsed));
            save("boot", boot);
            save("package", "");
            save("started", Long.toString(until));
            return;
        }
        long from = Math.max(cursor, until - TimeUnit.DAYS.toMillis(7));
        if (until <= from) {
            return;
        }
        UsageStatsManager manager = context.getSystemService(UsageStatsManager.class);
        UsageEvents events = manager.queryEvents(from, until);
        UsageEvents.Event event = new UsageEvents.Event();
        String active = sameBoot && from == cursor ? state("package") : null;
        String savedStart = active != null ? state("started") : null;
        long started = savedStart != null ? Long.parseLong(savedStart) : from;
        SQLiteDatabase database = getWritableDatabase();
        // Lưu hàng đợi và mốc đã đọc cùng một giao dịch để tránh mất/đếm trùng.
        database.beginTransaction();
        try {
            while (events.hasNextEvent()) {
                events.getNextEvent(event);
                switch (event.getEventType()) {
                    case UsageEvents.Event.ACTIVITY_RESUMED:
                        if (!Objects.equals(active, event.getPackageName())) {
                            if (active != null) {
                                enqueue(active, started, event.getTimeStamp());
                            }
                            active = event.getPackageName();
                            started = event.getTimeStamp();
                        }
                        break;
                    case UsageEvents.Event.ACTIVITY_PAUSED:
                    case UsageEvents.Event.ACTIVITY_STOPPED:
                        if (Objects.equals(active, event.getPackageName())) {
                            enqueue(Objects.requireNonNull(active), started, event.getTimeStamp());
                            active = null;
                        }
                        break;
                    case UsageEvents.Event.SCREEN_NON_INTERACTIVE:
                    case UsageEvents.Event.DEVICE_SHUTDOWN:
                        if (active != null) {
                            enqueue(active, started, event.getTimeStamp());
                        }
                        active = null;
                        break;
                    default:
                        break;
                }
            }
            if (active != null) {
                enqueue(active, started, until);
                started = until;
            }
            save("package", active == null ? "" : active);
            save("started", Long.toString(started));
            save("cursor", Long.toString(until));
            save("elapsed", Long.toString(elapsed));
            save("boot", boot);
            database.setTransactionSuccessful();
        } finally {
            database.endTransaction();
        }
    }

    private void enqueue(String packageName, long from, long to) throws JSONException {
        if (packageName.trim().isEmpty() || to <= from || packageName.equals(context.getPackageName())
                || packageName.equals(homePackage()) || packageName.equals("com.android.systemui")) {
            return;
        }
        String appName;
        try {
            appName = context.getPackageManager().getApplicationLabel(
                    context.getPackageManager().getApplicationInfo(packageName, 0)).toString();
        } catch (Exception exception) {
            appName = "Ứng dụng chưa nhận diện";
        }
        long start = from;
        while (start < to) {
            long midnight = Instant.ofEpochMilli(start).atZone(USAGE_ZONE).toLocalDate()
                    .plusDays(1).atStartOfDay(USAGE_ZONE).toInstant().toEpochMilli();
            long end = Math.min(midnight, to);
            int seconds = (int) ((end - start) / 1000);
            if (seconds > 0) {
                JSONObject body = new JSONObject();
                body.put("packageName", packageName);
                body.put("appName", appName);
                body.put("startedAt", Instant.ofEpochMilli(start).toString());
                body.put("endedAt", Instant.ofEpochMilli(end).toString());
                body.put("durationSeconds", seconds);
                ContentValues values = new ContentValues();
                values.put("body", body.toString());
                getWritableDatabase().insertOrThrow("queue", null, values);
                String day = Instant.ofEpochMilli(start).atZone(USAGE_ZONE).toLocalDate().toString();
                save("total:" + day, Integer.toString(total(day) + seconds));
            }
            start = end;
        }
    }

    public PendingUsage pending() throws JSONException {
        List<Long> ids = new ArrayList<>();
        JSONArray records = new JSONArray();
        try (Cursor cursor = getReadableDatabase().rawQuery("SELECT id,body FROM queue ORDER BY id LIMIT 100", null)) {
            while (cursor.moveToNext()) {
                ids.add(cursor.getLong(0));
                records.put(new JSONObject(cursor.getString(1)));
            }
        }
        return new PendingUsage(ids, records);
    }

    public void remove(List<Long> ids) {
        if (!ids.isEmpty()) {
            String placeholders = String.join(",", Collections.nCopies(ids.size(), "?"));
            String[] arguments = new String[ids.size()];
            for (int index = 0; index < ids.size(); index++) {
                arguments[index] = ids.get(index).toString();
            }
            getWritableDatabase().delete("queue", "id IN (" + placeholders + ")", arguments);
        }
    }

    public int activeSeconds(long now) {
        String packageName = state("package");
        if (packageName == null || packageName.trim().isEmpty()
                || packageName.equals(context.getPackageName()) || packageName.equals(homePackage())
                || packageName.equals("com.android.systemui")) {
            return 0;
        }
        String elapsed = state("elapsed");
        if (elapsed == null || !bootCount().equals(state("boot"))) {
            return 0;
        }
        return (int) (Math.max(0, SystemClock.elapsedRealtime() - Long.parseLong(elapsed)) / 1000);
    }

    public int total(String day) {
        String value = state("total:" + day);
        return value == null ? 0 : Integer.parseInt(value);
    }

    public boolean clockProblem() {
        return "true".equals(state("clockProblem"));
    }

    public void confirmClock() {
        String cursor = state("cursor");
        if (cursor != null && Math.abs(Long.parseLong(cursor) - System.currentTimeMillis()) <= 120000) {
            save("clockProblem", "false");
        }
    }

    public boolean warned(String day, int threshold) {
        ContentValues values = new ContentValues();
        values.put("day", day);
        values.put("threshold", threshold);
        values.put("at", Instant.now().toString());
        return getWritableDatabase().insertWithOnConflict("warnings", null, values,
                SQLiteDatabase.CONFLICT_IGNORE) == -1L;
    }

    public boolean hasWarned(String day, int threshold) {
        try (Cursor cursor = getReadableDatabase().rawQuery(
                "SELECT 1 FROM warnings WHERE day=? AND threshold=?",
                new String[]{day, Integer.toString(threshold)})) {
            return cursor.moveToFirst();
        }
    }

    private String bootCount() {
        return Integer.toString(Settings.Global.getInt(context.getContentResolver(), Settings.Global.BOOT_COUNT, 0));
    }

    public static class PendingUsage {
        public final List<Long> ids;
        public final JSONArray records;

        public PendingUsage(List<Long> ids, JSONArray records) {
            this.ids = ids;
            this.records = records;
        }
    }
}
