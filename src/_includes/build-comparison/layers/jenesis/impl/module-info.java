/**
 * @jenesis.pin com.fasterxml.jackson.core 2.15.4
 */
module demo.library.impl {
    requires com.fasterxml.jackson.core;
    requires demo.library.api;

    provides demo.library.api.Jackson with demo.library.impl.JacksonImpl;
}
