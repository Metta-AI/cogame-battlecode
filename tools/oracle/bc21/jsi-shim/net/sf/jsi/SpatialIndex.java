// A NO-OP STAND-IN for `net.sf.jsi:jsi:1.1.0-SNAPSHOT`, which was published
// only to jcenter (shut down 2022) and to the Sonatype OSS SNAPSHOTS
// repository (expired). Both 404 today.
//
// It can affect nothing. `world/ObjectInfo.java` calls only
// `robotIndex.init/add/delete` and NEVER QUERIES the index - seven call
// sites, all writes - so nothing it computes can reach the game. The
// `parity-oracle-bc21` job re-proves that on every run by asserting
// `ObjectInfo.java`'s sha256 against the value in `deps.lock`: if upstream
// ever starts READING the index, the hash changes and the job fails loudly
// rather than lying.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in any image stage.
package net.sf.jsi;

import java.util.Properties;

public interface SpatialIndex {
    void init(Properties props);
    void add(Rectangle r, int id);
    boolean delete(Rectangle r, int id);
}
