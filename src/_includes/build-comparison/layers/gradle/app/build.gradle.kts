plugins {
    application
    id("com.gradleup.shadow")
}

java {
    toolchain.languageVersion = JavaLanguageVersion.of(25)
}

dependencies {
    implementation(project(path = ":library", configuration = "shadow"))
    implementation("com.fasterxml.jackson.core:jackson-core:2.22.3")
}

application {
    mainClass = "demo.app.Main"
}
