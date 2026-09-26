plugins {
    java
    id("com.bakdata.gradle.avro") version "2.0.1"
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
    implementation("org.apache.avro:avro:1.12.2")
}
