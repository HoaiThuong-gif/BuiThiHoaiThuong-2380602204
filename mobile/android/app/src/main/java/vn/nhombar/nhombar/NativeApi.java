package vn.nhombar.nhombar;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import org.json.JSONObject;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public final class NativeApi {
    private NativeApi() { }

    public static synchronized void configureEndpoint(Context context, String baseUrl) throws Exception {
        URL url = new URL(baseUrl);
        boolean debug = (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        if (url.getUserInfo() != null || !("https".equals(url.getProtocol())
                || debug && "http".equals(url.getProtocol()))) {
            throw new IllegalStateException("Kết nối chưa được bảo vệ.");
        }
        Vault vault = new Vault(context);
        JSONObject current = vault.json("credentials");
        if (current == null) {
            return;
        }
        current.put("baseUrl", baseUrl.replaceAll("/+$", ""));
        vault.put("credentials", current.toString());
    }

    public static synchronized void credentials(Context context, JSONObject body) {
        new Vault(context).put("credentials", body.toString());
    }

    public static synchronized JSONObject refresh(Context context) throws Exception {
        Vault vault = new Vault(context);
        JSONObject credentials = vault.json("credentials");
        if (credentials == null) {
            throw new DeviceProblem("Con hãy nhờ bố mẹ kết nối lại điện thoại.", true);
        }
        HttpResult response = raw(context, credentials, "/api/auth/refresh",
                new JSONObject().put("refreshToken", credentials.getString("refreshToken")).toString(), false);
        if (response.status != 200) {
            boolean expired = response.status == 401 || response.status == 403;
            throw new DeviceProblem(expired
                    ? "Phiên đăng nhập đã kết thúc. Con hãy nhờ bố mẹ kiểm tra."
                    : "Dịch vụ đang tạm gián đoạn. Điện thoại sẽ thử kết nối lại.", expired);
        }
        JSONObject tokens = new JSONObject(response.body);
        credentials.put("accessToken", tokens.getString("accessToken"));
        credentials.put("refreshToken", tokens.getString("refreshToken"));
        vault.put("credentials", credentials.toString());
        return tokens;
    }

    public static synchronized String request(Context context, String path) throws Exception {
        return request(context, path, null);
    }

    public static synchronized String request(Context context, String path, String body) throws Exception {
        Vault vault = new Vault(context);
        JSONObject credentials = vault.json("credentials");
        if (credentials == null) {
            throw new IllegalStateException("Con cần đăng nhập lại.");
        }
        HttpResult response = raw(context, credentials, path, body, true);
        if (response.status == 401) {
            refresh(context);
            credentials = vault.json("credentials");
            response = raw(context, credentials, path, body, true);
        }
        if (response.status < 200 || response.status > 299) {
            String message = "Chưa cập nhật được. Hãy thử lại khi có mạng.";
            try {
                message = new JSONObject(response.body).optString("message", message);
            } catch (Exception ignored) {
                // Phản hồi không phải JSON vẫn dùng thông báo dễ hiểu.
            }
            throw new DeviceProblem(message);
        }
        return response.body;
    }

    private static HttpResult raw(Context context, JSONObject credentials, String path,
                                  String body, boolean bearer) throws Exception {
        URL url = new URL(credentials.getString("baseUrl").replaceAll("/+$", "") + path);
        boolean debug = (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        if (!("https".equals(url.getProtocol()) || debug && "http".equals(url.getProtocol()))) {
            throw new IllegalStateException("Kết nối chưa được bảo vệ. Hãy liên hệ người cung cấp ứng dụng.");
        }
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        try {
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(20000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("Accept", "application/json");
            if (bearer) {
                connection.setRequestProperty("Authorization", "Bearer " + credentials.getString("accessToken"));
            }
            if (body != null) {
                connection.setRequestMethod("POST");
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json");
                try (OutputStream output = connection.getOutputStream()) {
                    output.write(body.getBytes(StandardCharsets.UTF_8));
                }
            }
            int status = connection.getResponseCode();
            InputStream stream = status >= 200 && status <= 299
                    ? connection.getInputStream() : connection.getErrorStream();
            String response = "";
            if (stream != null) {
                try (java.io.Reader reader = new java.io.InputStreamReader(stream, StandardCharsets.UTF_8)) {
                    StringBuilder text = new StringBuilder();
                    char[] buffer = new char[4096];
                    int count;
                    while ((count = reader.read(buffer)) != -1) {
                        text.append(buffer, 0, count);
                    }
                    response = text.toString();
                }
            }
            return new HttpResult(status, response);
        } catch (IOException exception) {
            throw new DeviceProblem("Chưa liên lạc được với dịch vụ. Điện thoại sẽ thử kết nối lại.");
        } finally {
            connection.disconnect();
        }
    }

    private static class HttpResult {
        final int status;
        final String body;

        HttpResult(int status, String body) {
            this.status = status;
            this.body = body;
        }
    }
}
