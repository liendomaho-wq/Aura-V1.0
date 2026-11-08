package com.ciberdefensa.aura;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** Foreground consent host present ONLY in the separate instrumentation UID. */
public final class VpnInstrumentationActivity extends Activity {
    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView label = new TextView(this);
        label.setText("Aura: real VPN integration in isolated test application");
        setContentView(label);
    }
}
