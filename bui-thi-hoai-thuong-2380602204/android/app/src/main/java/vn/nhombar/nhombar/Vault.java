package vn.nhombar.nhombar;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Mã hóa dữ liệu riêng bằng khóa do AndroidKeyStore quản lý. */
public class Vault {
    private final SharedPreferences preferences;

    public Vault(Context context) {
        preferences = context.getSharedPreferences("nhombar_private", Context.MODE_PRIVATE);
    }

    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        java.security.Key existingKey = store.getKey("nhombar", null);
        if (existingKey instanceof SecretKey) {
            return (SecretKey) existingKey;
        }
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder("nhombar",
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build());
        return generator.generateKey();
    }

    public synchronized String get(String name) {
        String encoded = preferences.getString(name, null);
        if (encoded == null) {
            return null;
        }
        try {
            String[] parts = encoded.split(":");
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(),
                    new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
            return new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8);
        } catch (Exception exception) {
            throw new RuntimeException(exception);
        }
    }

    public synchronized void put(String name, String value) {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key());
            byte[] encrypted = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
            String encoded = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP)
                    + ":" + Base64.encodeToString(encrypted, Base64.NO_WRAP);
            preferences.edit().putString(name, encoded).commit();
        } catch (Exception exception) {
            throw new RuntimeException(exception);
        }
    }

    public synchronized void remove(String name) {
        preferences.edit().remove(name).commit();
    }

    public JSONObject json(String name) {
        String value = get(name);
        if (value == null) {
            return null;
        }
        try {
            return new JSONObject(value);
        } catch (Exception exception) {
            throw new RuntimeException(exception);
        }
    }
}
