/**
 * @jenesis.pin build.jenesis.launcher 0.5.3
 * @jenesis.layer jackson api demo.library.api
 * @jenesis.layer jackson provider demo.library.impl
 */
module demo.library {
    requires build.jenesis.launcher;
    requires demo.library.api;

    exports demo.library;
}
