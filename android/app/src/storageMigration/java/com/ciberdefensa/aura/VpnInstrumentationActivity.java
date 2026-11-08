package com.ciberdefensa.aura;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.view.WindowManager;
import android.widget.TextView;

/** Foreground consent host present ONLY in the separate instrumentation UID. */
public final class VpnInstrumentationActivity extends Activity {
    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        // A long software-emulator Gradle build can outlive the screen timeout.
        // These flags affect ONLY this isolated test host, not the shipped app.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        }
        TextView label = new TextView(this);
        label.setText("Aura: real VPN integration in isolated test application");
        setContentView(label);
    }
}
