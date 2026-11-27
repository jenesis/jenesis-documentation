### Blackbird: a setter that throws gives a different error message than stock Jackson, claiming a type mismatch

With the current 3.4.0-SNAPSHOT of Jackson (databind 3.4.0-SNAPSHOT), registering the Blackbird module changes the
message of the `DatabindException` you get when a bean's setter rejects a value. Without Blackbird the message is
the setter's own; with Blackbird it claims the value had the wrong type, although it had exactly the setter's type.

```java
public static class Guarded {
    private int age;
    private String code;

    public int getAge() { return age; }
    public void setAge(int age) {
        if (age < 0) throw new IllegalArgumentException("age must be >= 0");
        this.age = age;
    }

    public String getCode() { return code; }
    public void setCode(String code) {
        if (code.isEmpty()) throw new IllegalStateException("empty code");
        this.code = code;
    }
}

JsonMapper stock = JsonMapper.builder().build();
JsonMapper blackbird = JsonMapper.builder().addModule(new BlackbirdModule()).build();

stock.readValue("{\"age\":-1}", Guarded.class);
blackbird.readValue("{\"age\":-1}", Guarded.class);
```

Stock Jackson:

```
tools.jackson.databind.DatabindException: Problem setting property 'age': age must be >= 0
```

With Blackbird:

```
tools.jackson.databind.DatabindException: Problem setting property 'age' (expected type: [simple type, class int]; actual type: `java.lang.Integer`), problem: age must be >= 0
```

The same happens for `{"code":""}`, where stock Jackson reports `empty code` and Blackbird reports

```
Problem setting property 'code' (expected type: [simple type, class java.lang.String]; actual type: `java.lang.String`), problem: empty code
```

Builders (`@JsonDeserialize(builder = ...)`) whose `withXxx` methods throw are affected as well.

Expected: Blackbird is a drop-in optimisation, so with it registered a failing setter should produce exactly the
exception and message stock Jackson produces. Blackbird's own tests that compare its failures with stock Jackson's
fail as well.
