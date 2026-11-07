import java.io.InputStream;
import java.nio.file.Path;
import java.security.CodeSigner;
import java.security.MessageDigest;
import java.security.cert.Certificate;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

/** Verify every non-signature entry of an Android App Bundle as a signed JAR.
 * The expected SHA-256 is the configured upload certificate's fingerprint.
 * This checks archive integrity and signer identity, not Play App Signing.
 */
public final class VerifyAab {
    private static boolean isSignatureMetadata(String name) {
        String upper = name.toUpperCase(Locale.ROOT);
        if (!upper.startsWith("META-INF/")) return false;
        String base = upper.substring("META-INF/".length());
        if (base.contains("/")) return false;
        return base.equals("MANIFEST.MF") || base.endsWith(".SF") ||
            base.endsWith(".RSA") || base.endsWith(".DSA") || base.endsWith(".EC");
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2 || !args[1].matches("[0-9A-Fa-f]{64}")) {
            throw new IllegalArgumentException("Usage: VerifyAab <bundle> <certificate-sha256>");
        }
        String expected = args[1].toUpperCase(Locale.ROOT);
        Set<String> names = new HashSet<>();
        Set<String> metadataNames = new HashSet<>();
        int signedEntries = 0;
        byte[] buffer = new byte[32768];
        try (JarFile jar = new JarFile(Path.of(args[0]).toFile(), true)) {
            var entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String name = entry.getName();
                if (!names.add(name)) throw new SecurityException("Duplicate archive entry");
                if (name.toUpperCase(Locale.ROOT).startsWith("META-INF/") &&
                    !metadataNames.add(name.toUpperCase(Locale.ROOT))) {
                    throw new SecurityException("Ambiguous metadata entry");
                }
                if (entry.isDirectory() || isSignatureMetadata(name)) continue;
                try (InputStream input = jar.getInputStream(entry)) {
                    while (input.read(buffer) != -1) { /* trigger JAR signature verification */ }
                }
                CodeSigner[] signers = entry.getCodeSigners();
                if (signers == null || signers.length != 1) {
                    throw new SecurityException("Every bundle entry must have exactly one signer");
                }
                Certificate certificate = signers[0].getSignerCertPath().getCertificates().get(0);
                String actual = HexFormat.of().withUpperCase().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded())
                );
                if (!actual.equals(expected)) throw new SecurityException("Bundle signer does not match configured certificate");
                signedEntries++;
            }
        }
        if (signedEntries == 0) throw new SecurityException("Bundle contains no signed entries");
        System.out.println("AAB_SIGNED_ENTRIES=" + signedEntries);
        System.out.println("CERT_SHA256=" + expected);
    }
}
