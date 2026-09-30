package demo.app;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.jspecify.annotations.Nullable;
import org.slf4j.LoggerFactory;
import picocli.CommandLine;

public class Main {

    public static void main(String[] args) throws Exception {
        String name = first(args);
        String json = new ObjectMapper().writeValueAsString(Map.of("greeting", Greeter.greet(name == null ? "world" : name)));
        LoggerFactory.getLogger(Main.class).info(json);
        System.out.println(CommandLine.Help.Ansi.OFF.string(json));
    }

    private static @Nullable String first(String[] args) {
        return args.length == 0 ? null : args[0];
    }
}
