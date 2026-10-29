package vn.nhombar.nhombar;

import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Build;
import android.os.Bundle;

/** Chỉ có trong debug và vẫn chỉ chấp nhận emulator thử nghiệm dùng riêng. */
public class UsageProbe extends Instrumentation {
    private boolean confirmed;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        confirmed = arguments != null && "true".equals(arguments.getString("confirmDisposable"));
        start();
    }

    @Override
    public void onStart() {
        Bundle result = new Bundle();
        try {
            if (!confirmed) {
                throw new IllegalStateException("Pass confirmDisposable=true only for the disposable test emulator; its usage queue will be reset.");
            }
            if (!Build.MODEL.contains("sdk_gphone")) {
                throw new IllegalStateException("Use only the disposable test emulator.");
            }
            Context context = getTargetContext();
            ResolveInfo home = context.getPackageManager().resolveActivity(
                    new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                    PackageManager.MATCH_DEFAULT_ONLY);
            String homePackage = home != null && home.activityInfo != null ? home.activityInfo.packageName : null;
            try (UsageReader reader = new UsageReader(context)) {
                reader.bindDevice("isolated-usage-probe");
                reader.collect(System.currentTimeMillis());
                result.putString("homePackage", homePackage);
                result.putString("records", reader.pending().records.toString());
            }
            finish(-1, result);
        } catch (Exception exception) {
            result.putString("error", exception.toString());
            finish(0, result);
        }
    }
}
