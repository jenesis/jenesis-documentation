package build;

import module java.base;
import build.jenesis.Make;

public class Reproducible {

    private static final String EXPECTED = "ab2a7fb75f2aeea7b971dd7f03cb5191c43c3f3244c3a1cd406ef4e8f968dc67";

    static void main(String[] args) throws Exception {
        Make.Result result = new Make("build.jenesis.Project").build("stage");
        if (result.code() != 0) {
            throw new IllegalStateException("The build exited with a non-zero status");
        }
        Path jar = Path.of("target/stage/maven/output/demo/app/demo.app/1.0.0/demo.app-1.0.0.jar");
        String digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(jar)));
        if (!digest.equals(EXPECTED)) {
            throw new IllegalStateException(jar + " has SHA-256 " + digest + " where " + EXPECTED + " was recorded");
        }
        System.out.println(jar.getFileName() + " has the recorded SHA-256 " + digest);
    }
}
