package demo.app;

import org.slf4j.LoggerFactory;

public class Main {

    public static void main(String[] args) {
        String greeting = Greeter.greet(args.length == 0 ? "world" : args[0]);
        LoggerFactory.getLogger(Main.class).info(greeting);
        System.out.println(greeting);
    }
}
