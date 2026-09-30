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

dependencies {
    implementation("org.slf4j:slf4j-api:2.0.20")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.22.3")
    implementation("info.picocli:picocli:4.7.7")
    implementation("org.jspecify:jspecify:1.0.1")
}
