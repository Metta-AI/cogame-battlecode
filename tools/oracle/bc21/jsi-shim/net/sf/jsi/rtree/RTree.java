// See ../SpatialIndex.java. A no-op stand-in for the dead `net.sf.jsi`
// artifact: every method does nothing and returns the declared type.
package net.sf.jsi.rtree;

import java.util.Properties;

import net.sf.jsi.Rectangle;
import net.sf.jsi.SpatialIndex;

public class RTree implements SpatialIndex {
    public void init(Properties props) { }
    public void add(Rectangle r, int id) { }
    public boolean delete(Rectangle r, int id) { return true; }
}
