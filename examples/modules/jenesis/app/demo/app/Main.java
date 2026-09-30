package demo.app;

import demo.greeter.Greeter;
import org.slf4j.LoggerFactory;

public class Main {

    public static void main(String[] args) {
        String greeting = Greeter.greet("world");
        LoggerFactory.getLogger(Main.class).info(greeting);
        System.out.println(greeting);
    }
}
