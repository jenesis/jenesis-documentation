package demo.library;

import build.jenesis.launcher.Launcher;
import demo.library.api.Jackson;
import java.lang.invoke.MethodHandles;

public class Library {

    public static String version() {
        return Launcher.instance(MethodHandles.lookup(), "jackson", Jackson.class).version();
    }
}
