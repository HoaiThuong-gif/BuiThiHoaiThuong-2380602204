package vn.nhombar.nhombar;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public class FamilyMessagingService extends FirebaseMessagingService {
    @Override
    public void onNewToken(String token) {
        new Vault(this).put("fcmToken", token);
        FamilyPushEvents.emit("token");
    }

    @Override
    public void onMessageReceived(RemoteMessage message) {
        String noticeId = message.getData().get("noticeId");
        if (noticeId != null) {
            String binding = message.getData().get("binding");
            FamilyPushEvents.show(this, noticeId, binding == null ? "" : binding);
        }
    }
}
