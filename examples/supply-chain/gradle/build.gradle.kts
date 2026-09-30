import dev.sigstore.KeylessVerifier
import dev.sigstore.VerificationOptions.CertificateMatcher
import dev.sigstore.VerificationOptions
import dev.sigstore.bundle.Bundle
import dev.sigstore.strings.StringMatcher

buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath("dev.sigstore:sigstore-java:2.3.0")
    }
}

plugins {
    java
}

group = "demo"
version = "1.0.0"

java {
    toolchain.languageVersion = JavaLanguageVersion.of(25)
}

repositories {
    mavenCentral()
}

val sigstore = configurations.create("sigstore")

dependencies {
    implementation("org.slf4j:slf4j-api:2.0.20")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.22.3")
    implementation("info.picocli:picocli:4.7.7")
    implementation("org.jspecify:jspecify:1.0.1")
    implementation("dev.sigstore:protobuf-specs:0.5.2")

    sigstore("dev.sigstore:protobuf-specs:0.5.2@jar.sigstore.json")
}

val verifySigstore = tasks.register("verifySigstore") {
    val bundles: FileCollection = sigstore
    val jars: FileCollection = configurations.runtimeClasspath.get()
    doLast {
        val verifier = KeylessVerifier.builder().sigstorePublicDefaults().build()
        val options = VerificationOptions.builder().addCertificateMatchers(
            CertificateMatcher.fulcio()
                .issuer(StringMatcher.string("https://token.actions.githubusercontent.com"))
                .subjectAlternativeName(StringMatcher.regex("https://github.com/sigstore/protobuf-specs/.*"))
                .build()
        ).build()
        bundles.forEach { bundle ->
            val jar = jars.single { it.name == bundle.name.removeSuffix(".sigstore.json") }
            verifier.verify(jar.toPath(), Bundle.from(bundle.toPath(), Charsets.UTF_8), options)
            println("Sigstore verified: ${jar.name}")
        }
    }
}

tasks.compileJava {
    dependsOn(verifySigstore)
}
