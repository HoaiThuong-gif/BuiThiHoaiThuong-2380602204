package vn.nhombar.nhombar;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                && "true".equals(new Vault(context).get("monitoring"))) {
            try {
                context.startForegroundService(new Intent(context, GuardService.class));
            } catch (Exception exception) {
                new Vault(context).put("error", "Hãy mở NhomBar để tiếp tục cập nhật thời gian.");
            }
        }
    }
}
