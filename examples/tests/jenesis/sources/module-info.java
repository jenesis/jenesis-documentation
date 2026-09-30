/**
 * @jenesis.release 25
 * @jenesis.main demo.app.Main
 * @jenesis.pin org.slf4j 2.0.20
 * @jenesis.pin com.fasterxml.jackson.databind 2.22.3
 * @jenesis.pin info.picocli 4.7.7
 * @jenesis.pin org.jspecify 1.0.1
 */
module demo.app {
    requires org.slf4j;
    requires com.fasterxml.jackson.databind;
    requires info.picocli;
    requires static org.jspecify;

    exports demo.app to demo.app.test;
}
