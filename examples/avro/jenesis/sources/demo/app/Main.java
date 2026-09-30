package demo.app;

import demo.user.User;

public class Main {

    public static void main(String[] args) {
        System.out.println(User.newBuilder().setName("Ada").setScore(42).build());
    }
}
