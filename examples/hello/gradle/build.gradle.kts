plugins {
    application
}

java {
    toolchain.languageVersion = JavaLanguageVersion.of(25)
}

application {
    mainClass = "demo.hello.Main"
}
