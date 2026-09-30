package demo.app.test;

import static org.junit.jupiter.api.Assertions.assertEquals;

import demo.app.Greeter;
import org.junit.jupiter.api.Test;

class GreeterTest {

    @Test
    void greets() {
        assertEquals("Hello, world!", Greeter.greet("world"));
    }
}
