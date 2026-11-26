# HTTP method restrictions (`@HttpPost`, `@HttpGet`, ...) are silently not enforced for many actions

The `@HttpGet`, `@HttpPost`, `@HttpPut`, `@HttpDelete`, ... and `@AllowedHttpMethod` annotations are supposed to
restrict the HTTP methods an action answers: a request with another method gets `405 Method Not Allowed` with an
`Allow` header listing the permitted methods (or the action's bad-request result where it names one), and the
action does not run. In several ordinary situations the restriction is ignored and the action runs for any HTTP
method.

## What I see

With the default stack of `struts-default`, a `GET` request reaches each of these actions and they answer `200`,
although every one of them is meant to be POST-only:

1. The annotation is on `execute()` and the action is mapped without a `method` attribute:

   ```java
   public class ExecutePost extends ActionSupport {
       @HttpPost
       @Override
       public String execute() { ... }
   }
   ```
   ```xml
   <action name="ExecutePost" class="...ExecutePost"/>
   ```
   The same annotation on a method named in the mapping (`method="save"`) is enforced, and so is an `@HttpPost` on
   the class. Only the implicit `execute()` is let through.

2. The annotation is inherited rather than repeated:
   - `@HttpPost class ClassPost extends ActionSupport` is enforced, `class SubOfClassPost extends ClassPost {}` is not;
   - a subclass that overrides an `@HttpPost public String save()` of its base class without repeating the
     annotation is not restricted any more;
   - an annotation on an interface (on the interface type, or on a method the interface declares, a default method
     included) is lost when the action reaches that interface only through its superclass
     (`class Sub extends ImplementsMarker {}`) or through another interface that extends it
     (`interface Derived extends PostOnly {}`, `class Action implements Derived`).

3. Two bundled interceptor stacks do not check HTTP methods at all: an action in a package extending
   `rest-default` (the REST plugin's `restDefaultStack`) or `struts-bean-validation` (the Bean Validation plugin's
   `beanValidationDefaultStack`) that is annotated `@HttpPost` answers a `GET` with `200`. The same action class in a
   package extending `struts-default` answers `405` with `Allow: POST`. Every other bundled stack that binds request
   parameters does check them.

## What I expect

- The restriction of the method that is going to be invoked applies whether the method was named in the mapping or
  is the implicit `execute()`.
- An annotation is found through the hierarchy of the action class: on the invoked method itself first, otherwise
  on the nearest declaration of that method walking up the classes, looking at each class before the interfaces it
  implements (and their super-interfaces) and only then at its superclass. So a method annotation declared in a
  superclass wins over a different one declared on an interface the action implements. If no method annotation is
  found, the class-level annotation is looked up the same way (class, then its interfaces and their
  super-interfaces, then the superclass).
- Only a declaration that the invoked method can actually stand for counts: an annotated `private`, package-private
  or `static` method of the same name in an ancestor class or interface must not restrict a public action method.
- What works today keeps working: a method named explicitly in the mapping that does not exist still fails with
  `NoSuchMethodException` naming it, for any HTTP method. An action without an `execute()` method that is invoked
  implicitly must not fail in the HTTP method check (an unknown handler may still serve it); class-level
  annotations and the `http-method` restriction of the XML mapping still apply to it. Where a method annotation is
  found the class-level one is not consulted, as today. `POST` to all of the POST-only actions above keeps
  answering `200`.
- `restDefaultStack` and `beanValidationDefaultStack` enforce the restrictions like the stacks of `struts-default`.
  For the REST plugin this means the check is made against the real HTTP method of the request, not against the
  `_method` parameter the REST action mapper uses to tunnel `PUT` and `DELETE` through a `POST` form: an
  `update()` annotated `@HttpPut` alone answers a real `PUT` and rejects a `POST` with `_method=put` (`405`,
  `Allow: PUT`); annotated `@HttpPost @HttpPut` it answers both. An action implementing `HttpMethodAware` is still
  told the real method.

Affected: 7.x (seen on the current 7.5.0-SNAPSHOT), modules `struts2-core`, `struts2-rest-plugin` and
`struts2-bean-validation-plugin`.
