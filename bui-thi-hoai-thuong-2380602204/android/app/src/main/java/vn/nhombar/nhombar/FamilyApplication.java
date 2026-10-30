package vn.nhombar.nhombar;

import android.app.Application;

public class FamilyApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        FamilyPushEvents.channel(this);
    }
}
