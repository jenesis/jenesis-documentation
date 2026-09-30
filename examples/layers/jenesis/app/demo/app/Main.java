package demo.app;

import com.fasterxml.jackson.core.json.PackageVersion;
import demo.library.Library;

public class Main {

    public static void main(String[] args) {
        System.out.println("app " + PackageVersion.VERSION + ", library " + Library.version());
    }
}
