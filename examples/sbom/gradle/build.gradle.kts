import org.cyclonedx.model.Component
import org.cyclonedx.model.ExternalReference
import org.cyclonedx.model.License
import org.cyclonedx.model.LicenseChoice
import org.cyclonedx.model.OrganizationalEntity

plugins {
    java
    `maven-publish`
    id("org.cyclonedx.bom") version "3.4.1"
}

group = "demo"
version = "1.0.0"
description = "A small command-line application used to compare build tools."

java {
    toolchain.languageVersion = JavaLanguageVersion.of(25)
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.slf4j:slf4j-api:2.0.20")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.22.3")
    implementation("info.picocli:picocli:4.7.7")
    implementation("org.jspecify:jspecify:1.0.1")
}

val projectUrl = "https://example.org/demo-app"
val scmUrl = "https://github.com/example/demo-app"

tasks.cyclonedxDirectBom {
    projectType = Component.Type.APPLICATION
    includeConfigs = listOf("runtimeClasspath")
    xmlOutput.convention(null as RegularFile?)
    organizationalEntity = OrganizationalEntity().apply {
        name = "Example Org"
        urls = listOf("https://example.org")
    }
    licenseChoice = LicenseChoice().apply {
        addLicense(License().apply { id = "Apache-2.0" })
    }
    externalReferences = listOf(
        ExternalReference().apply { type = ExternalReference.Type.WEBSITE; url = projectUrl },
        ExternalReference().apply { type = ExternalReference.Type.VCS; url = scmUrl },
    )
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
            artifact(tasks.cyclonedxDirectBom.flatMap { it.jsonOutput }) {
                classifier = "cyclonedx"
                extension = "json"
            }
            pom {
                name = "Demo App"
                description = project.description
                url = projectUrl
                inceptionYear = "2026"
                licenses {
                    license {
                        name = "Apache-2.0"
                        url = "https://www.apache.org/licenses/LICENSE-2.0.txt"
                    }
                }
                organization {
                    name = "Example Org"
                    url = "https://example.org"
                }
                developers {
                    developer {
                        id = "jdoe"
                        name = "Jane Doe"
                        email = "jane.doe@example.org"
                    }
                }
                scm {
                    url = scmUrl
                    connection = "scm:git:$scmUrl.git"
                }
            }
        }
    }
    repositories {
        maven { url = uri(layout.buildDirectory.dir("repo")) }
    }
}
