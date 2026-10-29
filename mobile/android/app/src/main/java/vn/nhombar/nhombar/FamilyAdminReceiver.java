package vn.nhombar.nhombar;

import android.app.admin.DeviceAdminReceiver;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import java.util.Collections;

public class FamilyAdminReceiver extends DeviceAdminReceiver {
    @Override
    public void onEnabled(Context context, Intent intent) {
        DevicePolicyManager manager = context.getSystemService(DevicePolicyManager.class);
        if (manager.isDeviceOwnerApp(context.getPackageName()) && Build.VERSION.SDK_INT >= 30) {
            manager.setUserControlDisabledPackages(new ComponentName(context, FamilyAdminReceiver.class),
                    Collections.singletonList(context.getPackageName()));
        }
    }
}
