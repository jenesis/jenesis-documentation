plugins {
    java
}

group = "demo"
version = "1.0.0"

java {
    toolchain.languageVersion = JavaLanguageVersion.of(25)
}

val java25 = sourceSets.create("java25")

tasks.compileJava {
    options.release = 21
}

tasks.jar {
    into("META-INF/versions/25") {
        from(java25.output)
    }
    manifest.attributes("Multi-Release" to true)
}
