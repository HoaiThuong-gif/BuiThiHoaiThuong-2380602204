package vn.nhombar.nhombar;

import android.app.Activity;
import android.app.admin.DevicePolicyManager;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public class ProvisioningComplianceActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        boolean owner = getSystemService(DevicePolicyManager.class).isDeviceOwnerApp(getPackageName());
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(40, 60, 40, 40);
        TextView message = new TextView(this);
        message.setText(owner
                ? "NhomBar đã được Android cho phép quản lý điện thoại này. Tiếp theo, mở NhomBar và quét mã trong hồ sơ của con trên điện thoại bố mẹ."
                : "Android chưa cấp quyền quản lý. Điện thoại vẫn có thể dùng NhomBar thông thường, nhưng chưa thể khóa ứng dụng khi hết giờ.");
        message.setTextSize(20f);
        content.addView(message);
        Button next = new Button(this);
        next.setText("Tiếp tục");
        next.setOnClickListener(view -> {
            setResult(owner ? RESULT_OK : RESULT_CANCELED);
            finish();
        });
        content.addView(next);
        setContentView(content);
    }
}
