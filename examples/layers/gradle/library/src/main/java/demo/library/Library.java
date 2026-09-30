package demo.library;

import com.fasterxml.jackson.core.json.PackageVersion;

public class Library {

    public static String version() {
        return PackageVersion.VERSION.toString();
    }
}
