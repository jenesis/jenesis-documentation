package demo.library.impl;

import com.fasterxml.jackson.core.json.PackageVersion;
import demo.library.api.Jackson;

public class JacksonImpl implements Jackson {

    @Override
    public String version() {
        return PackageVersion.VERSION.toString();
    }
}
