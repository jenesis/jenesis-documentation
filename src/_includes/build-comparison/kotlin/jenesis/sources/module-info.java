/**
 * @jenesis.release 25
 * @jenesis.main demo.app.MainKt
 * @jenesis.plugin kotlinc maven/org.jetbrains.kotlin/kotlin-serialization-compiler-plugin
 * @jenesis.pin kotlinc/maven/org.jetbrains.kotlin/kotlin-compiler-embeddable 2.4.20
 * @jenesis.pin kotlinc/maven/org.jetbrains.kotlin/kotlin-serialization-compiler-plugin 2.4.20
 */
module demo.app {
    requires kotlin.stdlib;
    requires kotlinx.serialization.json;
}
