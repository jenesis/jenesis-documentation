---
order: 19
title: Extending Jenesis Repository
description: How a module of your own adds to Jenesis Repository - the service seams it plugs into, what each one is for, a few providers in code, and a custom image built FROM the official one that carries them.
---

Jenesis Repository is assembled from Java modules, and every capability it has - a format, a storage backend, a
security feed, a background pass, a console page - is a module that *provides* a service another module *uses*.
Nothing registers a capability by name: a module on the module path is discovered through `java.util.ServiceLoader`,
and taking it away takes the capability with it. An extension of your own works exactly the same way, so it can do
anything a built-in module does, through the same seams.

## How an extension plugs in

An extension is an ordinary Java module. Its `module-info.java` requires the module that declares the service and
says which class provides it:

```java
module com.example.repository.notice {
    requires build.jenesis.repository.store;      // PublicationObserver, ArtifactDescriptor, ArtifactStore
    requires build.jenesis.repository.settings;   // SettingsContributor, Setting

    provides build.jenesis.repository.store.PublicationObserver
            with com.example.repository.notice.NoticeObserver;
    provides build.jenesis.repository.settings.SettingsContributor
            with com.example.repository.notice.NoticeSettings;
}
```

Each release publishes the free modules to Maven Central under the group `build.jenesis`, every artifact named
for its module, so a build resolves `build.jenesis:build.jenesis.repository.store` like any other dependency.

A few rules hold for every seam:

- **Discovery happens in one place.** Each service interface has a static that finds its providers - usually
  `installed()`, `resolve(...)` or `discovered()` on the interface itself - and that is the only code in the
  product that calls `ServiceLoader` for it. An extension never looks providers up itself; it provides one.
- **Every seam states its contract.** The javadoc of each service interface ends with a section titled
  *Contract*: which thread calls it, whether a call may be repeated, what a failure does, whether it may reach
  the network. Read it before implementing - it is the part a test of your extension should hold you to.
- **A seam decides how many providers take part.** Some take every provider (every format serves, every
  observer is told), some take at most one and name it by a setting (`jenrepo.gc=mark-sweep`), and a few always
  resolve exactly one, with a built-in default you can replace (the storage backend). The table below says
  which.
- **An extension adds, it does not replace.** The image's own modules are found before yours, so a module of
  yours with the same name as one the image carries is ignored. Replacing a built-in is done by selecting
  another provider through its setting, not by shadowing a module.

## A few providers in code

### React to a publish

A `PublicationObserver` is told after an artifact has been committed, removed, cached from an upstream or held.
The descriptor names the artifact - ecosystem, coordinate, version, path, content hash - and the store is already
scoped to the tenant and repository it went into:

```java
public final class NoticeObserver implements PublicationObserver {

    @Override
    public void onPublished(ArtifactDescriptor artifact, ArtifactStore store) throws IOException {
        if (artifact.coordinate() == null || artifact.hash() == null) {
            return;   // a checksum, a signature or generated metadata: nothing to note
        }
        String note = artifact.ecosystem() + " " + artifact.coordinate() + " " + artifact.version();
        store.write("notices/" + artifact.hash(), new ByteArrayInputStream(note.getBytes(StandardCharsets.UTF_8)));
    }
}
```

The contract asks three things of it. It is called concurrently from every publishing request, so it keeps no
state in fields. It may be called again for the same artifact, so what it writes must be an upsert. And it must
not call out of the process inline: it leaves a durable note in the store it is handed, and a background pass
delivers it. A thrown exception is logged and the publish stands - an observer never decides whether an
artifact is accepted. That is what the screening seams are for.

### Keep derived state right by walking

What an observer derives, a `WalkConsumer` can rebuild. The scheduled walk enumerates the store once for every
consumer that listens on it, so a consumer is how an extension back-fills its state the first time it is
installed and repairs it afterwards - never by walking the store on its own:

```java
public final class NoticeRebuild implements WalkConsumer {

    @Override
    public String name() {
        return "notice-rebuild";   // its jenrepo.notice-rebuild=false switch, and its name on the walks screen
    }

    @Override
    public void onRetained(ArtifactDescriptor artifact, ArtifactStore store) throws IOException {
        new NoticeObserver().onPublished(artifact, store);   // the same upsert the live event performs
    }
}
```

The walk hands `onRetained` every artifact the store serves, at least once per pass. Which walk runs it, and
how often, is the operator's choice on the walks screen, since a pass that reads the whole store is a cost.

### Offer a setting

A `SettingsContributor` puts an extension's settings in the catalogue, so they appear on the settings screens,
in `GET /api/settings` and in `jenrepo settings` for exactly as long as the module is installed:

```java
public final class NoticeSettings implements SettingsContributor {

    @Override
    public List<Setting> settings() {
        return List.of(new Setting("notice-target", "Notices", "Notice target",
                "Where the notice drain delivers what the observer recorded. Empty delivers nothing.",
                Setting.Kind.URI, "", true).standard());
    }
}
```

The final `true` says the setting applies as soon as it is saved. A setting a module reads only as the server
starts says `false`, and a write to it answers that it waits for a restart.

### Add a console page

A `ConsoleModuleProvider` names a Spring `@Configuration` class that contributes the page's controllers, and the
menu entries that lead to them. The page renders through the console's shared layout, so it looks like every
other page:

```java
public final class NoticeConsoleModule implements ConsoleModuleProvider {

    @Override
    public String name() {
        return "notices";
    }

    @Override
    public Class<?> configuration() {
        return NoticeConsoleConfig.class;   // a @Configuration declaring the page's @Controller
    }

    @Override
    public boolean enabledByDefault() {
        return true;
    }

    @Override
    public List<NavEntry> navEntries() {
        return List.of(new NavEntry("Notices", "/ui/notices", NavEntry.Access.ADMIN, NavEntry.Group.OPERATIONS));
    }
}
```

A page returns a view name and a model, never markup built as a string, and a page that needs to see the whole
store starts that work off the request and shows its progress rather than waiting for it.

The same configuration can add panels to the console's dashboard: a `DashboardContributor` bean answers the
panels a viewer sees - a title opening its page, a headline figure, a few lines - for the tenant they work in:

```java
@Bean
DashboardContributor noticePanel(NoticeLog log) {
    return viewer -> List.of(new DashboardPanel("Notices", "/ui/notices",
            Integer.toString(log.pending(viewer.tenant())), "notices wait for delivery",
            DashboardPanel.Tone.NEUTRAL, List.of()));
}
```

A panel is drawn on every visit, so it costs a few point reads at most; a figure that needs every repository is
counted in the background and read back with the time it was counted. A contributor that fails is shown as
unreadable while the other panels render.

### Store artifacts somewhere else

An `ArtifactStoreProvider` is a storage backend. It is chosen by name with `jenrepo.store`, and the filesystem
store is the default when nothing is chosen:

```java
public final class ExampleStoreProvider implements ArtifactStoreProvider {

    @Override
    public String name() {
        return "example";   // selected with JENREPO_STORE=example
    }

    @Override
    public ArtifactStore create(UnaryOperator<String> config) {
        return new ExampleStore(ArtifactStoreProvider.required(config, "jenrepo.example.bucket", name()));
    }
}
```

A backend is the one seam where the contract is long: compare-and-set writes, paged listings and a missing key
answering as absent rather than as an error are what every other part of the product relies on. The store's
contract kit is a test suite to run a new backend through before trusting it with artifacts.

## Ship it in an image

The official image is built so that an image built `FROM` it can add modules without touching how it starts. Its
module path ends with the folder `/app/extensions/modulepath`, and its class path with `/app/extensions/classpath/*`.
The official image creates neither, and `java` skips a folder that does not exist, so they only matter once an
image copies jars into them:

```dockerfile
FROM jenesisbuild/jenesis-repository
COPY com.example.repository.notice.jar /app/extensions/modulepath/
```

```bash
docker build -t my-repository .
docker run -p 8080:8080 -v repository-data:/data my-repository
```

That is the whole image. A module that provides a service the server uses is resolved when the server starts
and found by the seam's discovery, so no argument changes and the image needs no `ENTRYPOINT` of its own. Put
jars in the two folders like this:

- **A module goes in `modulepath/`**, and so does any library it needs that the image does not already carry. A
  jar with no `module-info` of its own still works there, as an automatic module.
- **A jar that cannot be a module goes in `classpath/`.** It comes after the image's own class path, so it can
  add classes and `META-INF/services` entries but never replace a class the image already has.
- **The image's own jars always win.** Each is named on the module path ahead of the folder, so a jar of yours
  that carries a module the image already has is not the one loaded. Two jars claiming one package stop the
  server at start with an error naming both, rather than running with either.

JVM options - memory, system properties - go in `JDK_JAVA_OPTIONS`, which `java` reads before the image's own
arguments:

```dockerfile
ENV JDK_JAVA_OPTIONS="-XX:MaxRAMPercentage=75"
```

To confirm the extension was found, open *Settings → Modules* in the console and then *Modules by contract*, or
run `jenrepo spi`: every seam is listed with the providers the running server discovered, yours among them.

## The seams

Every seam below is a service interface in the free modules; the package is `build.jenesis.repository` followed
by the part shown before the name. *Every* means each installed provider takes part, *one, by setting* means at
most one is used and a setting names it when several are installed, and *one* means exactly one always
resolves, with a built-in default.

### Formats and storage

| Seam | What it is for | Providers |
|---|---|---|
| `format.RepositoryFormat` | A repository protocol: the request paths it claims, and how it serves and accepts one ecosystem's artifacts. Its sub-interfaces add proxying, layout and import. | Every |
| `format.CombinedFormat` | A repository type that holds several formats at once. | Every |
| `format.java.bridge.ModuleView` | The Java-module view of a Maven artifact, published beside it. | Every |
| `format.FetcherProvider` | The transport that talks to upstream registries: the HTTP client, revalidation, negative caching. | One, by setting |
| `store.ArtifactStoreProvider` | A storage backend for artifacts and everything the product keeps. | One (filesystem) |
| `store.TenantsProvider` | Where the directory of tenants is kept. | One, by setting |
| `metadata.MetadataProvider` | The store of each version's consolidated metadata document. | One |
| `maintenance.StorageNamespace` | The key spaces a module owns in the store, so its data can be found and reclaimed. | Every |
| `gc.GarbageCollectorProvider` | How unreferenced content is reclaimed. | One, by setting |
| `gc.walk.GcRoots` | Where a format keeps the pointers that keep content alive. | Every |

### Screening what comes in

| Seam | What it is for | Providers |
|---|---|---|
| `compliance.QualityInspector` | Reads an artifact into what the gate judges: its coordinate, licences and dependencies, per format. | Every |
| `compliance.GatePolicyProvider` | A dimension of the publish gate, such as a licence policy or a known-exploited check. | Every |
| `compliance.SignalSourceProvider` | A security signal: a vulnerability feed, a known-exploited catalogue, an exploit-probability model, maintainer health, a report column. | Every |
| `compliance.SignatureScheme` | How one kind of signature is read and verified, and what it states once checked. | Every |
| `compliance.SignerTrustProvider` | The trust a repository holds for signers, laid over the inspectors that verify signatures. | Every |
| `compliance.VexProvider` | Suppressing an advisory a product states does not apply to it (VEX). | One |
| `compliance.ProvenanceSignerProvider` | How the repository signs the provenance it attests. | One, by setting |
| `gate.HoldReleaseObserver` | What a reviewer's release of a held artifact also does. | Every |
| `gate.RetroLicensePlanner` | A dry run of what licence enforcement would newly hold. | One |
| `findings.FindingsProvider` | The persistent ledger of findings. | One |
| `health.HealthLedgerProvider` | The persistent record of maintainer health. | One |

### Background work

| Seam | What it is for | Providers |
|---|---|---|
| `maintenance.MaintenanceTaskProvider` | A scheduled background pass. | Every |
| `walk.WalkConsumer` | Derived state rebuilt from the one scheduled walk of the store. | Every |
| `walk.WalkProvider` | How the store is enumerated for the walk. | One, by setting |
| `cleanup.RetentionProvider` | The retention engine that decides what ages out. | One, by setting |
| `staging.StagingProvider` | Staging an upload before it is promoted. | One, by setting |
| `inventory.DownloadTrackerProvider` | Recording downloads, for retention by last use. | One, by setting |
| `events.EventSink` | Delivering repository events (a webhook, a queue). | Every |
| `store.PublicationObserver` | Being told of every publish, removal, cached copy and hold. | Every |

### The server and access

| Seam | What it is for | Providers |
|---|---|---|
| `server.kernel.ServerModuleProvider` | A server feature module: its endpoints, contributed as a Spring configuration. | Every |
| `server.RepositoryRoutingProvider` | How a request is mapped to a tenant and repository. | One (`fixed`) |
| `server.AuthorizationManagerProvider` | The policy that decides whether a request may proceed. | One, by setting |
| `server.spi.CapabilityContributor` | What a module adds to `GET /api/capabilities`. | Every |
| `server.spi.ImportEdgeProvider` | Taking over the import endpoint with a richer importer. | One |
| `server.spi.KeyUsageTrackerProvider` | Recording where and when each credential is used. | One, by setting |
| `server.spi.RateLimiterProvider` | Metering request rates. | One, by setting |
| `server.spi.TokenExchangeProvider` | Exchanging a workload identity token for a credential. | One, by setting |
| `gateway.RedirectHandlerProvider` | Answering a download with a redirect to where the bytes are served. | Every |
| `upstream.UpstreamCredentialSourceProvider` | Where the credentials for upstream registries are kept. | One, by setting |
| `upstream.UpstreamTokenIssuer` | Minting a short-lived credential a cloud registry expects. | Every |
| `importer.ImportSourceProvider` | Reading another repository manager's contents for a migration. | Every |
| `audit.AuditTrailProvider` | Where the audit trail is kept. | One, by setting |
| `dependents.spi.DependentsQueryProvider` | The reverse-dependency index behind "what uses this". | One |
| `search.SearchQueryProvider` | The free-text search index. | One |

### The console and operations

| Seam | What it is for | Providers |
|---|---|---|
| `ui.ConsoleModuleProvider` | A console module: its pages, menu entries and security. | Every |
| `ui.ConsoleLayout.Extension` | The fragments of the shared layout a console fills. | Every |
| `settings.SettingsContributor` | A module's settings, in the catalogue every surface lists. | Every |
| `observation.ObservabilitySource` | A module's health checks, metrics and task states. | Every |
| `posture.SafetyAdvisor` | Warnings about unsafe settings a module owns, on the security-posture screen. | Every |

### The build cache

| Seam | What it is for | Providers |
|---|---|---|
| `cache.protocol.CacheProtocol` | One build tool's cache protocol, read as an address in the shared cache. | Every |
| `cache.storage.CacheStorageProvider` | Where cache entries are kept. | One (in the artifact store) |
