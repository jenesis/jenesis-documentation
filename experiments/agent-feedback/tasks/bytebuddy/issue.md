# Constructor exit advice rejects valid compact frames with long or double parameters

Applying constructor exit advice with the default argument backup rejects valid bytecode when the constructor has a
`long` or `double` parameter and a compact stack map frame appears before the super constructor call. The
transformation throws an `IllegalStateException` before the class can be loaded.

Reproduced on Byte Buddy 1.18.14 and on master.

## Reproducer

```java
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;

import static net.bytebuddy.matcher.ElementMatchers.isConstructor;

public class ConstructorFrameReproducer {
    public static class Parent {
        public Parent(int value) {}
    }

    public static class Child extends Parent {
        public Child(long value) {
            super(value == 0 ? 1 : 2);
        }
    }

    public static class EmptyExit {
        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void exit() {}
    }

    public static void main(String[] args) {
        new ByteBuddy()
                .redefine(Child.class)
                .visit(Advice.to(EmptyExit.class).on(isConstructor()))
                .make();
    }
}
```

fails with

```
java.lang.IllegalStateException: public ConstructorFrameReproducer$Child(long) dropped implicit 'this' frame
    at net.bytebuddy.asm.Advice$StackMapFrameHandler$Default$WithPreservedArguments$WithArgumentCopy.translateFrame(Advice.java:7879)
```

Changing the parameter to `int` makes it work, and so does any other parameter type that is not `long` or `double`.
The same constructor with a `double` parameter fails the same way.

Expected: the class is transformed, loads, and the constructor behaves as before (`new Child(0L)` passes 1 to the
super constructor, any other value 2).

## A related case

The same check is there to refuse a constructor whose frames drop the uninitialized `this` before the super
constructor call has run - Byte Buddy cannot add exit advice to such a constructor and says so with the same
"dropped implicit 'this' frame" error. That refusal is missed when the constructor's bytecode carries a full frame
(`F_FULL`, with `UNINITIALIZED_THIS` as its only local) before the super constructor call and a later frame chops
that local: the transformation then succeeds without an error and produces a class that the JVM's verifier rejects
when it is loaded. It should be refused at transformation time, like the case without a full frame. Dropping an
already initialized `this` after the super constructor call, in contrast, is legal and has to keep working.
