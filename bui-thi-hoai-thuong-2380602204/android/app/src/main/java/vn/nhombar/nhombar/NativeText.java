package vn.nhombar.nhombar;

import android.content.Context;
import org.json.JSONObject;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;

public final class NativeText {
    private static JSONObject english;

    private NativeText() { }

    public static String get(Context context, String text) {
        if (!"en".equals(new Vault(context).get("language"))) {
            return text;
        }
        if (english == null) {
            try (InputStream input = context.getAssets().open("flutter_assets/assets/english.json");
                 Reader reader = new InputStreamReader(input, StandardCharsets.UTF_8)) {
                StringBuilder content = new StringBuilder();
                char[] buffer = new char[4096];
                int count;
                while ((count = reader.read(buffer)) != -1) {
                    content.append(buffer, 0, count);
                }
                String json = content.toString();
                if (json.startsWith("\uFEFF")) {
                    json = json.substring(1);
                }
                english = new JSONObject(json);
            } catch (Exception exception) {
                english = new JSONObject();
            }
        }
        if (english.has(text)) {
            try {
                return english.getString(text);
            } catch (Exception exception) {
                throw new RuntimeException(exception);
            }
        }
        if (text.startsWith("Giờ sử dụng:")) {
            return text.replace("Giờ sử dụng:", "Phone time:")
                    .replace("Nếu đã hết thời gian hôm nay, con có thể dùng lại vào ngày mai.",
                            "If you have used all your time today, you can use your phone again tomorrow.");
        }
        if (text.startsWith("Con còn ")) {
            return text.replace("Con còn ", "You have ")
                    .replace(" phút sử dụng điện thoại. Hãy chuẩn bị kết thúc hoạt động hiện tại nhé.",
                            " minutes of phone time left. Please get ready to finish what you are doing.");
        }
        return text;
    }
}
