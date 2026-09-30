plugins {
    `java-library`
    id("com.gradleup.shadow")
}

java {
    toolchain.languageVersion = JavaLanguageVersion.of(25)
}

dependencies {
    implementation("com.fasterxml.jackson.core:jackson-core:2.15.4")
}

tasks.shadowJar {
    relocate("com.fasterxml.jackson.core", "demo.library.shaded.jackson.core")
    mergeServiceFiles()
}
