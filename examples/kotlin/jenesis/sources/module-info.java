/**
 * @jenesis.release 25
 * @jenesis.main demo.app.MainKt
 * @jenesis.plugin kotlin:tool maven/org.jetbrains.kotlin/kotlin-serialization-compiler-plugin
 * @jenesis.pin kotlin:tool/maven/org.jetbrains.kotlin/kotlin-compiler-embeddable 2.4.20
 * @jenesis.pin kotlin:tool/maven/org.jetbrains.kotlin/kotlin-serialization-compiler-plugin 2.4.20
 * @jenesis.pin kotlin.stdlib 2.4.20
 * @jenesis.pin kotlinx.serialization.json 1.11.0
 */
module demo.app {
    requires kotlin.stdlib;
    requires kotlinx.serialization.json;
}
