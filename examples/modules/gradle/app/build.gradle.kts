plugins {
    java
}

java {
    toolchain.languageVersion = JavaLanguageVersion.of(25)
}

dependencies {
    implementation(project(":greeter"))
    implementation("org.slf4j:slf4j-api:2.0.20")
}
