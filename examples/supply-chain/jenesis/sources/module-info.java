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
 * @jenesis.pin maven/com.fasterxml.jackson.core/jackson-annotations/pom 2.22 SHA-256/38c3ba52a0eade3e3eacc5b13499d56e1038ccbad8ec4bb79426dc21432b46d0
 * @jenesis.pin maven/com.fasterxml.jackson.core/jackson-core/pom 2.22.3 SHA-256/bc74c18b24f3ebbfd42741f2b29b37eca9b25e512e6fa7add77f6973cee50bf1
 * @jenesis.pin maven/com.fasterxml.jackson.core/jackson-databind/pom 2.22.3 SHA-256/27a5c6657b955d088daf586f2be9769224e33618ab4f44682a1b36ed98f7b904
 * @jenesis.pin maven/com.fasterxml.jackson/jackson-base/pom 2.22.3 SHA-256/1991ff35885b389eb29c23ae318c8eca66562915205bdeea53c722a5bd1b3bcb
 * @jenesis.pin maven/com.fasterxml.jackson/jackson-bom/pom 2.22.3 SHA-256/8f499c6a8c017bb987a1a73b91f705c22fe24ec2777e7055c7a2a913f14b5440
 * @jenesis.pin maven/com.fasterxml.jackson/jackson-parent/pom 2.22 SHA-256/7d45a7efb69df207bed7cc54b87a0bb012f10952c095570a273b49485da0d129
 * @jenesis.pin maven/com.fasterxml/oss-parent/pom 79 SHA-256/9206b7dd67fb138036576c3dfca947a2a8f3e2c4d2d9c1f2d1dea519b3a4dae1
 * @jenesis.pin maven/dev.sigstore/protobuf-specs/pom 0.5.2 SHA-256/f7479ebd996d520be5ad951a53e4fc4c1b1eca6223b7ae6155d6cdf0a90bfb79
 * @jenesis.pin maven/info.picocli/picocli/pom 4.7.7 SHA-256/1b18d363134df66631d2b9f7475068d734225ba389cdf9082a1bd8bda90d57d3
 * @jenesis.pin maven/org.jspecify/jspecify/pom 1.0.1 SHA-256/55b38bf1a7b1d8ea518cf2f4f3ae9aaa236e61bbf0b6bd31ffb49753a059dd5e
 * @jenesis.pin maven/org.junit/junit-bom/pom 5.14.3 SHA-256/08a02856e487c9357f9b29e38745f8ae805848111e72d15aad0352338f1632e1
 * @jenesis.pin maven/org.slf4j/slf4j-api/pom 2.0.20 SHA-256/2e625c3f553cddd49f8554cea9926cbf70673b3d6833464f0c5a02f4d9130594
 * @jenesis.pin maven/org.slf4j/slf4j-bom/pom 2.0.20 SHA-256/351a3d34f0886942268efcf291708c48dfadce7f2643837efdb4a6954d4e6c62
 * @jenesis.pin maven/org.slf4j/slf4j-parent/pom 2.0.20 SHA-256/d931cf99cfd3554d322809df03c43ef897082cd480d6ff91b44d8f067ca324c8
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
