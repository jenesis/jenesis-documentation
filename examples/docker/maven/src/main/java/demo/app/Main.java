package demo.app;

public class Main {

    public static void main(String[] args) {
        System.out.println(Greeter.greet(args.length == 0 ? "world" : args[0]));
    }
}
