# A restricted resource is served anyway when a component is handed the resource itself

## What I see

My application restricts resources with its `IAuthorizationStrategy`: `isResourceAuthorized(IResource, PageParameters)`
returns `false` for some of them (with wicket-auth-roles the same is done by `@AuthorizeResource` on the resource
class). That works as long as the resource is requested by the URL of a mounted or shared `ResourceReference`:
the request is refused, by default with a 403.

It does not work when the very same resource instance is given to a component. The component then renders its own
listener URL instead of a resource URL, and a request to that URL streams the resource to anybody who can see the
page. The strategy is never asked. I found this with

- `new ResourceLink<>("link", resource)`, while `new ResourceLink<>("link", resourceReference)` is refused as expected;
- `new Image("image", resource)`, an `Image` that takes the resource from its model, and the entries of an image's
  `srcset` (the additional resources passed to the `Image` constructor);
- `new ImageButton("button", resource)`;
- `AjaxDownloadBehavior` of wicket-extensions constructed with an `IResource`, while the one constructed with a
  `ResourceReference` is refused;
- the export links of a data table's `ExportToolbar` in wicket-extensions, which serve the exported data from a
  resource the toolbar builds.

Which of the two happens is decided only by the constructor the application calls; nothing in the rendered page
shows it.

## How to reproduce

```java
public class DownloadPage extends WebPage {
    public DownloadPage() {
        IResource report = new ByteArrayResource("text/plain", "secret".getBytes());
        add(new ResourceLink<Void>("report", report));
    }
}

// in Application#init()
getSecuritySettings().setAuthorizationStrategy(new IAuthorizationStrategy.AllowAllAuthorizationStrategy() {
    @Override
    public boolean isResourceAuthorized(IResource resource, PageParameters parameters) {
        return false;
    }
});
```

Render the page and click the link (in a test: `tester.startPage(DownloadPage.class); tester.clickLink("report", false);`).
The response is 200 with the body `secret`, and `isResourceAuthorized` was never called. With wicket-auth-roles, a
resource class annotated `@AuthorizeResource("ADMIN")` is downloaded through such a link or image by a user who
only has the role `USER`.

## What I expect

A resource that a component or a behavior serves from its own listener URL is authorized exactly like one that is
requested by a resource URL, on every request:

- the authorization strategy is asked once for each resource that is about to be served, with the resource
  instance the component holds, and - as on the resource URL route - never with `null` parameters: a listener URL
  carries no resource parameters, so they are empty `PageParameters`. An image with a `srcset` asks about its
  `src` resource and about every `srcset` entry it serves;
- a refusal is handled by the `IUnauthorizedResourceRequestListener` of the application's security settings, as it
  is for a resource URL, so by default the response is the same 403 with the same error message, and a listener
  the application installed is the one that is called;
- nothing of a refused resource reaches the response: its `respond` is not called, and `ResourceLink#onClick()`
  does not run for it either;
- resources the strategy allows, and everything served through a `ResourceReference`, behave as before.
