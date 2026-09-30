/**
 * @jenesis.release 25
 * @jenesis.main demo.app.Main
 * @jenesis.alias protobuf.specs dev.sigstore/protobuf-specs
 * @jenesis.pin com.fasterxml.jackson.core/jackson-annotations 2.22 SHA-256/21ddb598807d3a51a876704eb979d9296e1c6a6f47ab1826ff88c6d6a127a2d0
 * @jenesis.pin com.fasterxml.jackson.core/jackson-core 2.22.3 SHA-256/8a501126a385b25841915d839508f8a66e2a0dbc8a6709d055ef3b3e852b094c
 * @jenesis.pin com.fasterxml.jackson.core/jackson-databind 2.22.3 SHA-256/556db5439e206114346043f68d200497dc96a0bca62a360a81784092ebd0e0a9
 * @jenesis.pin com.fasterxml.jackson.databind 2.22.3 SHA-256/556db5439e206114346043f68d200497dc96a0bca62a360a81784092ebd0e0a9
 * @jenesis.pin dev.sigstore/protobuf-specs 0.5.2 SHA-256/e2368fd262a9bec078dee8868fc82682cb648ec21906f8b399e348977f3e3a3e
 * @jenesis.pin info.picocli 4.7.7 SHA-256/f86e30fffd10d2b13b8caa8d4b237a7ee61f2ffccf5b1941de718b765d235bf8
 * @jenesis.pin info.picocli/picocli 4.7.7 SHA-256/f86e30fffd10d2b13b8caa8d4b237a7ee61f2ffccf5b1941de718b765d235bf8
 * @jenesis.pin org.jspecify 1.0.1 SHA-256/070d75f261fe4c5b8202508366715f7f2d4660f88c8ef7e6d3575e48c9683b66
 * @jenesis.pin org.jspecify/jspecify 1.0.1 SHA-256/070d75f261fe4c5b8202508366715f7f2d4660f88c8ef7e6d3575e48c9683b66
 * @jenesis.pin org.slf4j 2.0.20 SHA-256/7e1446499b359675d8aabe6af2de86b85e72ae8a2a932c0b40d0e5ba57097439
 * @jenesis.pin org.slf4j/slf4j-api 2.0.20 SHA-256/7e1446499b359675d8aabe6af2de86b85e72ae8a2a932c0b40d0e5ba57097439
 * @jenesis.signature OpenPGP/60200AC4AE761F1614D6C46766D68DAA073BE985 org.slf4j/*
 * @jenesis.signature OpenPGP/28118C070CB22A0175A2E8D43D12CA2AC19F3181 com.fasterxml.jackson.core/*
 * @jenesis.signature OpenPGP/AA417737BD805456DB3CBDDE6601E5C08DCCBB96 info.picocli/*
 * @jenesis.signature OpenPGP/41CD49B4EF5876F9E9F691DABAC30622339994C4 org.jspecify/*
 * @jenesis.signature Sigstore/github.com/sigstore/protobuf-specs dev.sigstore/*
 */
module demo.app {
    requires org.slf4j;
    requires com.fasterxml.jackson.databind;
    requires info.picocli;
    requires static org.jspecify;
    requires static protobuf.specs;
}
